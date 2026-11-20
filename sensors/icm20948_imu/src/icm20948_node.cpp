// icm20948_node: minimal ROS 2 driver for the ICM-20948 IMU on the Waveshare IMX219-83
// camera board, wired to the Jetson Nano's 40-pin header (pin 3 = SDA, pin 5 = SCL -> /dev/i2c-1).
//
// What it does, in plain words:
//   * sets the chip to fixed, documented settings (sample rate, measuring range, low-pass filter);
//   * lets the chip collect samples in its own buffer (FIFO) at its own steady clock;
//   * empties that buffer every ~10 ms and publishes every sample as sensor_msgs/Imu;
//   * gives each sample a time stamp from a model "t(k) = offset + period * k" (k = sample number),
//     fitted to the moments the buffer was read. This removes the jitter of Linux scheduling and of
//     the slow (100 kHz) I2C bus; what remains is a small constant delay (I2C read + the chip's
//     low-pass filter), which the camera-IMU calibration (Kalibr) estimates as the time offset.
//
// Topics:  imu/data_raw     sensor_msgs/Imu          (no orientation; orientation_covariance[0] = -1)
//          imu/temperature  sensor_msgs/Temperature  (1 Hz, useful for the long still recording)
//
// Register addresses and scale factors: TDK InvenSense ICM-20948 datasheet (DS-000189).

#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cmath>
#include <cstring>
#include <deque>
#include <limits>
#include <memory>
#include <random>
#include <stdexcept>
#include <string>
#include <thread>

#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/imu.hpp"
#include "sensor_msgs/msg/temperature.hpp"

namespace
{
// ---- registers (datasheet section 7/8) ----
constexpr uint8_t REG_BANK_SEL = 0x7F;  // present in every bank, bank number in bits [5:4]
// bank 0
constexpr uint8_t B0_WHO_AM_I = 0x00;
constexpr uint8_t B0_USER_CTRL = 0x03;
constexpr uint8_t B0_LP_CONFIG = 0x05;
constexpr uint8_t B0_PWR_MGMT_1 = 0x06;
constexpr uint8_t B0_PWR_MGMT_2 = 0x07;
constexpr uint8_t B0_INT_STATUS_2 = 0x1B;  // bits [4:0] FIFO overflow, cleared on read
constexpr uint8_t B0_TEMP_OUT_H = 0x39;
constexpr uint8_t B0_FIFO_EN_1 = 0x66;
constexpr uint8_t B0_FIFO_EN_2 = 0x67;
constexpr uint8_t B0_FIFO_RST = 0x68;
constexpr uint8_t B0_FIFO_MODE = 0x69;
constexpr uint8_t B0_FIFO_COUNTH = 0x70;
constexpr uint8_t B0_FIFO_R_W = 0x72;
// bank 2
constexpr uint8_t B2_GYRO_SMPLRT_DIV = 0x00;
constexpr uint8_t B2_GYRO_CONFIG_1 = 0x01;
constexpr uint8_t B2_ODR_ALIGN_EN = 0x09;
constexpr uint8_t B2_ACCEL_SMPLRT_DIV_1 = 0x10;
constexpr uint8_t B2_ACCEL_SMPLRT_DIV_2 = 0x11;
constexpr uint8_t B2_ACCEL_CONFIG = 0x14;

constexpr uint8_t kWhoAmI = 0xEA;
constexpr double kBaseRateHz = 1125.0;        // output rate = 1125 Hz / (1 + divider)
constexpr double kStandardGravity = 9.80665;  // m/s^2 per g
constexpr double kDegToRad = M_PI / 180.0;
constexpr int kSampleBytes = 12;              // accel x,y,z then gyro x,y,z, int16 big endian
constexpr int kMaxSamplesPerRead = 20;        // 240 bytes per I2C transfer

int64_t clock_ns(clockid_t id)
{
  timespec ts{};
  clock_gettime(id, &ts);
  return static_cast<int64_t>(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

int16_t be16(const uint8_t * p) {return static_cast<int16_t>((p[0] << 8) | p[1]);}

class I2cDevice
{
public:
  I2cDevice(const std::string & path, uint16_t address)
  : address_(address)
  {
    fd_ = ::open(path.c_str(), O_RDWR);
    if (fd_ < 0) {
      throw std::runtime_error("cannot open " + path + ": " + std::strerror(errno));
    }
  }
  ~I2cDevice() {if (fd_ >= 0) {::close(fd_);}}
  I2cDevice(const I2cDevice &) = delete;
  I2cDevice & operator=(const I2cDevice &) = delete;

  void write_reg(uint8_t reg, uint8_t value)
  {
    uint8_t buf[2] = {reg, value};
    i2c_msg msg{address_, 0, 2, buf};
    i2c_rdwr_ioctl_data data{&msg, 1};
    if (ioctl(fd_, I2C_RDWR, &data) < 0) {
      throw std::runtime_error(std::string("I2C write failed: ") + std::strerror(errno));
    }
  }

  void read_regs(uint8_t reg, uint8_t * out, uint16_t len)
  {
    i2c_msg msgs[2] = {{address_, 0, 1, &reg}, {address_, I2C_M_RD, len, out}};
    i2c_rdwr_ioctl_data data{msgs, 2};
    if (ioctl(fd_, I2C_RDWR, &data) < 0) {
      throw std::runtime_error(std::string("I2C read failed: ") + std::strerror(errno));
    }
  }

private:
  int fd_{-1};
  uint16_t address_;
};
}  // namespace

class Icm20948Node : public rclcpp::Node
{
public:
  Icm20948Node()
  : Node("icm20948")
  {
    device_ = declare_parameter<std::string>("device", "/dev/i2c-1");
    address_ = declare_parameter<int>("address", 0x68);
    divider_ = declare_parameter<int>("sample_rate_div", 4);  // 4 -> 225 Hz
    gyro_range_dps_ = declare_parameter<int>("gyro_range_dps", 500);
    accel_range_g_ = declare_parameter<int>("accel_range_g", 4);
    gyro_dlpf_ = declare_parameter<int>("gyro_dlpf_cfg", 3);    // 3 -> 51.2 Hz bandwidth
    accel_dlpf_ = declare_parameter<int>("accel_dlpf_cfg", 3);  // 3 -> 50.4 Hz bandwidth
    poll_ms_ = declare_parameter<double>("poll_period_ms", 10.0);
    frame_id_ = declare_parameter<std::string>("frame_id", "imu");
    warmup_s_ = declare_parameter<double>("warmup_s", 2.0);
    window_s_ = declare_parameter<double>("clock_window_s", 30.0);

    gyro_code_ = range_code(gyro_range_dps_, {250, 500, 1000, 2000}, "gyro_range_dps");
    accel_code_ = range_code(accel_range_g_, {2, 4, 8, 16}, "accel_range_g");
    if (divider_ < 0 || divider_ > 255) {throw std::invalid_argument("sample_rate_div must be 0..255");}
    if (gyro_dlpf_ < 0 || gyro_dlpf_ > 7 || accel_dlpf_ < 0 || accel_dlpf_ > 7) {
      throw std::invalid_argument("dlpf_cfg must be 0..7");
    }
    const double gyro_lsb_per_dps[4] = {131.0, 65.5, 32.8, 16.4};
    const double accel_lsb_per_g[4] = {16384.0, 8192.0, 4096.0, 2048.0};
    gyro_scale_ = kDegToRad / gyro_lsb_per_dps[gyro_code_];          // raw -> rad/s
    accel_scale_ = kStandardGravity / accel_lsb_per_g[accel_code_];  // raw -> m/s^2
    nominal_period_ = (1.0 + divider_) / kBaseRateHz;

    imu_pub_ = create_publisher<sensor_msgs::msg::Imu>("imu/data_raw", rclcpp::QoS(1000).reliable());
    temp_pub_ = create_publisher<sensor_msgs::msg::Temperature>("imu/temperature", 10);

    dev_ = std::make_unique<I2cDevice>(device_, static_cast<uint16_t>(address_));
    configure_chip();
    RCLCPP_INFO(
      get_logger(),
      "ICM-20948 on %s at 0x%02x: %.3f Hz, gyro +-%d dps (DLPF %d), accel +-%d g (DLPF %d), "
      "reading every %.1f ms", device_.c_str(), address_, 1.0 / nominal_period_, gyro_range_dps_,
      gyro_dlpf_, accel_range_g_, accel_dlpf_, poll_ms_);

    worker_ = std::thread([this] {run();});
  }

  ~Icm20948Node() override
  {
    stop_ = true;
    if (worker_.joinable()) {worker_.join();}
    try {
      select_bank(0);
      dev_->write_reg(B0_USER_CTRL, 0x00);    // FIFO off
      dev_->write_reg(B0_PWR_MGMT_1, 0x41);   // sleep
    } catch (...) {
    }
  }

private:
  static int range_code(int value, std::initializer_list<int> allowed, const char * name)
  {
    int code = 0;
    for (int a : allowed) {
      if (a == value) {return code;}
      ++code;
    }
    throw std::invalid_argument(std::string(name) + " has an unsupported value");
  }

  void select_bank(int bank)
  {
    if (bank != current_bank_) {
      dev_->write_reg(REG_BANK_SEL, static_cast<uint8_t>(bank << 4));
      current_bank_ = bank;
    }
  }

  static void sleep_ms(int ms) {std::this_thread::sleep_for(std::chrono::milliseconds(ms));}

  void configure_chip()
  {
    current_bank_ = -1;
    select_bank(0);
    uint8_t who = 0;
    dev_->read_regs(B0_WHO_AM_I, &who, 1);
    if (who != kWhoAmI) {
      throw std::runtime_error("WHO_AM_I is not 0xEA - is this an ICM-20948 and is it wired to pins 3/5?");
    }
    dev_->write_reg(B0_PWR_MGMT_1, 0x80);  // full reset
    sleep_ms(100);
    current_bank_ = -1;                    // reset returns the chip to bank 0
    select_bank(0);
    dev_->write_reg(B0_PWR_MGMT_1, 0x01);  // awake, best available clock, temperature sensor on
    sleep_ms(50);
    dev_->write_reg(B0_PWR_MGMT_2, 0x00);  // all accel and gyro axes on
    dev_->write_reg(B0_LP_CONFIG, 0x00);   // no duty cycling = low-noise mode
    dev_->write_reg(B0_USER_CTRL, 0x00);   // FIFO off, internal I2C master (magnetometer) off
    sleep_ms(10);

    select_bank(2);
    dev_->write_reg(B2_GYRO_SMPLRT_DIV, static_cast<uint8_t>(divider_));
    dev_->write_reg(B2_GYRO_CONFIG_1, static_cast<uint8_t>((gyro_dlpf_ << 3) | (gyro_code_ << 1) | 1));
    dev_->write_reg(B2_ACCEL_SMPLRT_DIV_1, static_cast<uint8_t>((divider_ >> 8) & 0x0F));
    dev_->write_reg(B2_ACCEL_SMPLRT_DIV_2, static_cast<uint8_t>(divider_ & 0xFF));
    dev_->write_reg(B2_ACCEL_CONFIG, static_cast<uint8_t>((accel_dlpf_ << 3) | (accel_code_ << 1) | 1));
    dev_->write_reg(B2_ODR_ALIGN_EN, 0x01);  // accel and gyro sampled at the same instants

    select_bank(0);
    dev_->write_reg(B0_FIFO_EN_1, 0x00);   // no external-sensor data in the FIFO
    dev_->write_reg(B0_FIFO_EN_2, 0x1E);   // accel + gyro x/y/z, no temperature
    dev_->write_reg(B0_FIFO_MODE, 0x00);   // stream mode
    sleep_ms(50);                          // let the filters settle a little
    reset_fifo();
  }

  void reset_fifo()
  {
    select_bank(0);
    dev_->write_reg(B0_USER_CTRL, 0x00);
    dev_->write_reg(B0_FIFO_RST, 0x1F);
    dev_->write_reg(B0_FIFO_RST, 0x00);
    uint8_t clear = 0;
    dev_->read_regs(B0_INT_STATUS_2, &clear, 1);  // clear an old overflow flag
    dev_->write_reg(B0_USER_CTRL, 0x40);          // FIFO on
    // restart the time model
    sample_index_ = 0;
    observations_.clear();
    period_ = nominal_period_;
    offset_ = std::numeric_limits<double>::quiet_NaN();
    fifo_start_ = mono_seconds();
  }

  double mono_seconds() const
  {
    return static_cast<double>(clock_ns(CLOCK_MONOTONIC) - mono_ref_ns_) * 1e-9;
  }

  // Time model t(k) = offset + period * k, in monotonic seconds.
  // period: least-squares slope of (k_last, t_read) over the last clock_window_s seconds.
  // offset: lower envelope = smallest observed delay between a sample being in the FIFO and us
  //         noticing it; the reading moments are dithered so the envelope gets close to the real edge.
  void update_model(int64_t k_last, double t_read)
  {
    observations_.push_back({k_last, t_read});
    while (observations_.size() > 2 && observations_.back().t - observations_.front().t > window_s_) {
      observations_.pop_front();
    }
    const double span = observations_.back().t - observations_.front().t;
    if (span >= 1.0) {
      double mk = 0.0, mt = 0.0;
      for (const auto & o : observations_) {mk += static_cast<double>(o.k); mt += o.t;}
      mk /= observations_.size();
      mt /= observations_.size();
      double skt = 0.0, skk = 0.0;
      for (const auto & o : observations_) {
        const double dk = static_cast<double>(o.k) - mk;
        skt += dk * (o.t - mt);
        skk += dk * dk;
      }
      const double slope = skt / skk;
      if (std::fabs(slope / nominal_period_ - 1.0) < 0.05) {period_ = slope;}
    }
    double envelope = std::numeric_limits<double>::infinity();
    for (const auto & o : observations_) {
      envelope = std::min(envelope, o.t - period_ * static_cast<double>(o.k));
    }
    offset_ = envelope;
  }

  void read_temperature(int64_t stamp_ns)
  {
    uint8_t b[2];
    select_bank(0);
    dev_->read_regs(B0_TEMP_OUT_H, b, 2);
    sensor_msgs::msg::Temperature msg;
    msg.header.stamp = rclcpp::Time(stamp_ns, RCL_SYSTEM_TIME);
    msg.header.frame_id = frame_id_;
    msg.temperature = be16(b) / 333.87 + 21.0;  // datasheet: sensitivity 333.87 LSB/degC, 21 degC offset
    msg.variance = 0.0;
    temp_pub_->publish(msg);
  }

  void poll_once()
  {
    select_bank(0);
    uint8_t cnt[2];
    dev_->read_regs(B0_FIFO_COUNTH, cnt, 2);
    const double t_read = mono_seconds();  // after the count is known: every counted sample existed by now
    const int bytes = ((cnt[0] & 0x1F) << 8) | cnt[1];
    const int available = bytes / kSampleBytes;
    max_batch_ = std::max(max_batch_, available);
    if (available == 0) {return;}

    update_model(sample_index_ + available - 1, t_read);
    const bool publish = (t_read - fifo_start_) >= warmup_s_;

    // Wall-clock stamps (same clock as the camera driver): monotonic model + current offset.
    const int64_t m1 = clock_ns(CLOCK_MONOTONIC);
    const int64_t r = clock_ns(CLOCK_REALTIME);
    const int64_t m2 = clock_ns(CLOCK_MONOTONIC);
    const int64_t real_minus_mono = r - (m1 + m2) / 2;

    uint8_t buf[kMaxSamplesPerRead * kSampleBytes];
    int remaining = available;
    while (remaining > 0) {
      const int n = std::min(remaining, kMaxSamplesPerRead);
      dev_->read_regs(B0_FIFO_R_W, buf, static_cast<uint16_t>(n * kSampleBytes));
      for (int i = 0; i < n; ++i) {
        const uint8_t * p = buf + i * kSampleBytes;
        const double t_mono = offset_ + period_ * static_cast<double>(sample_index_);
        ++sample_index_;
        if (!publish) {continue;}
        int64_t stamp_ns = mono_ref_ns_ + static_cast<int64_t>(std::llround(t_mono * 1e9)) +
          real_minus_mono;
        if (stamp_ns <= last_stamp_ns_) {stamp_ns = last_stamp_ns_ + 1000; ++stamps_fixed_;}
        last_stamp_ns_ = stamp_ns;

        sensor_msgs::msg::Imu msg;
        msg.header.stamp = rclcpp::Time(stamp_ns, RCL_SYSTEM_TIME);
        msg.header.frame_id = frame_id_;
        msg.orientation.w = 1.0;
        msg.orientation_covariance[0] = -1.0;  // no orientation estimate
        msg.linear_acceleration.x = be16(p + 0) * accel_scale_;
        msg.linear_acceleration.y = be16(p + 2) * accel_scale_;
        msg.linear_acceleration.z = be16(p + 4) * accel_scale_;
        msg.angular_velocity.x = be16(p + 6) * gyro_scale_;
        msg.angular_velocity.y = be16(p + 8) * gyro_scale_;
        msg.angular_velocity.z = be16(p + 10) * gyro_scale_;
        imu_pub_->publish(msg);
        ++published_;
      }
      remaining -= n;
    }
  }

  void run()
  {
    std::mt19937 rng(12345);
    std::uniform_real_distribution<double> dither(0.0, 1.0);  // ms, breaks phase lock with the chip
    int64_t next = clock_ns(CLOCK_MONOTONIC);
    double last_status = mono_seconds(), last_temp = last_status, last_overflow_check = last_status;
    int consecutive_errors = 0;

    while (!stop_ && rclcpp::ok()) {
      next += static_cast<int64_t>((poll_ms_ + dither(rng)) * 1e6);
      const int64_t now = clock_ns(CLOCK_MONOTONIC);
      if (next < now) {next = now;}
      timespec ts{static_cast<time_t>(next / 1000000000LL), static_cast<long>(next % 1000000000LL)};
      clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, nullptr);

      try {
        const double t = mono_seconds();
        if (t - last_overflow_check >= 0.1) {
          last_overflow_check = t;
          uint8_t st = 0;
          select_bank(0);
          dev_->read_regs(B0_INT_STATUS_2, &st, 1);
          if (st & 0x1F) {
            ++overflows_;
            RCLCPP_WARN(get_logger(), "FIFO overflow (samples lost) - buffer reset, %.1f s gap", warmup_s_);
            reset_fifo();
            continue;
          }
        }
        poll_once();
        if (t - last_temp >= 1.0) {
          last_temp = t;
          read_temperature(clock_ns(CLOCK_REALTIME));
        }
        if (t - last_status >= 10.0) {
          last_status = t;
          RCLCPP_INFO(
            get_logger(), "published %ld, chip rate %.3f Hz, max %d samples per read, "
            "overflows %d, I2C errors %d, stamps nudged %d", static_cast<long>(published_),
            1.0 / period_, max_batch_, overflows_, i2c_errors_, stamps_fixed_);
          max_batch_ = 0;
        }
        consecutive_errors = 0;
      } catch (const std::exception & e) {
        ++i2c_errors_;
        RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 2000, "%s", e.what());
        if (++consecutive_errors >= 50) {
          RCLCPP_FATAL(get_logger(), "50 I2C errors in a row - stopping");
          rclcpp::shutdown();
          return;
        }
        current_bank_ = -1;  // unknown after a failed transfer
      }
    }
  }

  struct Observation {int64_t k; double t;};

  // parameters
  std::string device_, frame_id_;
  int address_, divider_, gyro_range_dps_, accel_range_g_, gyro_dlpf_, accel_dlpf_;
  int gyro_code_{0}, accel_code_{0};
  double poll_ms_, warmup_s_, window_s_;
  double gyro_scale_{0}, accel_scale_{0}, nominal_period_{0};

  // state
  std::unique_ptr<I2cDevice> dev_;
  int current_bank_{-1};
  const int64_t mono_ref_ns_{clock_ns(CLOCK_MONOTONIC)};
  int64_t sample_index_{0};
  std::deque<Observation> observations_;
  double period_{0}, offset_{0}, fifo_start_{0};
  int64_t last_stamp_ns_{0};
  int64_t published_{0};
  int max_batch_{0}, overflows_{0}, i2c_errors_{0}, stamps_fixed_{0};

  rclcpp::Publisher<sensor_msgs::msg::Imu>::SharedPtr imu_pub_;
  rclcpp::Publisher<sensor_msgs::msg::Temperature>::SharedPtr temp_pub_;
  std::atomic<bool> stop_{false};
  std::thread worker_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    auto node = std::make_shared<Icm20948Node>();
    rclcpp::spin(node);
  } catch (const std::exception & e) {
    RCLCPP_FATAL(rclcpp::get_logger("icm20948"), "%s", e.what());
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
