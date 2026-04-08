# HFI_ROS_WSS_Driver
A repository that maps incoming ROS2 stimulation magnitudes to the WSS stimulator.

## Table of Contents

- [Dependencies](#dependencies)
- [Setup Instructions](#setup-instructions)
- [Running the ROS WSS Driver](#running-the-ros-wss-driver)
- [Running Unit Tests](#running-unit-tests)
- [Debugging](#debugging)

## Dependencies
The table below lists the direct dependencies needed for this repository.

| **Dependency Name** | **Description** |
|---------------------|-----------------|
| `rclpy` | ROS2 Python client library used for subscriptions, launch, and node lifecycle. |
| `std_msgs` | Provides the `Float64` message type used for stimulation magnitudes. |
| `HFI_WSS_Python_Interface` | Git submodule containing the Python WSS interface wrapper and bundled WSS DLLs. |

## Setup Instructions

### Software Setup

1. **Clone the Repository**:
   ```bash
   git clone --recurse-submodules git@github.com:cwru-non-academic/HFI_ROS_WSS_Driver.git
   cd HFI_ROS_WSS_Driver
   ```

2. **Install Dependencies**:
   Ensure your ROS2 environment is sourced and that the Python wrapper dependency can be imported from the included submodule.

3. **Review Driver Configuration**:
   Update `config/default_ros_wss_driver_params.yaml` as needed.
   The ROS2 YAML specifies:
   - the app-owned WSS `Config/` directory path
   - the log file path
   - the serial port
   - whether to use the wrapper test transport
   - the WSS setup retry count
   - the WSS tick interval in milliseconds
   - up to nine ROS topic names mapped to `ch1` through `ch9`

4. **Compile the Package**:
   Build the package using `colcon`:
   ```bash
   colcon build --packages-select hfi_ros_wss_driver --symlink-install
   ```

## Running the ROS WSS Driver

1. **Create and Edit Configuration File**:
   Modify `default_ros_wss_driver_params.yaml` as needed to set your desired parameters.

2. **Launch the Driver**:
   Execute the following command, specifying the path to your configuration file:
   ```bash
   ros2 launch hfi_ros_wss_driver launch_ros_wss_driver.launch.py
   ```

3. **Publish a Test Command**:
   For the default channel 2 mapping:
   ```bash
   ros2 topic pub /dom/index/stimulation_value std_msgs/msg/Float64 "{data: 0.5}" --once
   ```

Incoming values are clamped to the range `[0.0, 1.0]` before being sent to `StimWithMode("chN", value)`.

## Running Unit Tests

No unit tests are currently included in this repository.

## Debugging

- Repo-owned WSS JSON configuration lives under `Config/`.
- The wrapper submodule remains at `HFI_WSS_Python_Interface/` and provides the Python package and `Cs_Libraries/` DLLs.
- `test_mode: true` switches the wrapper to its test transport instead of serial transport.
- `max_retries` defaults to `5` and `tick_interval_ms` defaults to `10`.
- The number of non-empty channel topics updates `Config/stimConfig.json` `maxWSS` automatically: 1-3 topics -> `1`, 4-6 topics -> `2`, 7-9 topics -> `3`.
- Leave a channel topic empty in the YAML to disable that channel subscription.
- The default example maps `/dom/index/stimulation_value` to `ch2`.
