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
   git clone --recurse-submodules git@github.com:cwru-non-academic/ROS_Python_WSS_Application.git
   cd ROS_Python_WSS_Application
   ```

2. **Install Dependencies**:
   Source your ROS2 environment and ensure `pythonnet` is available to the Python
   interpreter used by ROS. If it is not already installed, install the runtime
   prerequisite with that interpreter:

   ```bash
   python3 -m pip install -r requirements.txt
   ```

   A separate installation of `wss-py-wrapper` is no longer required. The build
   installs the pinned wrapper source and complete DLL payload together. Existing
   ROS/CLR environments can be reused; the CI development host versions below are
   not a new requirement to install a .NET SDK on the application computer.

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
   source install/setup.bash
   ```

### Updating an existing checkout

Stop the running node, then use the normal update/rebuild sequence:

```bash
git pull
git submodule sync --recursive
git submodule update --init --recursive
colcon build --packages-select hfi_ros_wss_driver --symlink-install
source install/setup.bash
```

Plain `git pull` does not guarantee the checked-out submodule follows the new
gitlink. The update command selects the exact reviewed pin, not the newest
library branch. Restart the node after rebuilding; replacing WSS assemblies
inside a running process is unsupported. No existing publisher/client code needs
to change. Retain existing YAML and calibration paths; the example YAML's absolute
paths are examples for an existing installation, not portable defaults.

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

Run the hardware-free contract/import/lifecycle tests from the repository root:

```bash
python3 -m unittest discover -s tests -v
```

ROS CI additionally builds with colcon on a **development baseline** of ROS 2
Humble / Ubuntu 22.04 x64, checks symlink and copied installs, resolves the same
launch command, and exercises all nine `Float64` topics through real rclpy/DDS
with a recording managed-layer double. It never opens a serial/BLE transport.
A separate Windows x64 CPython 3.12 / pythonnet 3.0.5 / .NET 9 host tests the
actual wrapper/Core model path with Core's in-memory emulator. See
[tests/BASELINE.md](tests/BASELINE.md) and [.github/ROS_COMPATIBILITY.md](.github/ROS_COMPATIBILITY.md).
These are development checks, not certification of every ROS distro or hardware.

The Windows job also executes the unchanged ten-case canonical NUnit corpus
through the same controller factory used by ROS node setup, preserving all
eighteen assertions. Its results, the separate model report and both native
layout reports form seven source-bound evidence files. Normal CI evidence is
not candidate approval: automatic promotion additionally requires the reviewed
v2 wrapper/CLI/ROS proof and a fresh preflight of the actual merged wrapper.

## Debugging

- Repo-owned WSS JSON configuration lives under `Config/`.
- The wrapper submodule remains at `HFI_WSS_Python_Interface/` and provides the Python package and `Cs_Libraries/` DLLs.
- `test_mode: true` switches the wrapper to its test transport instead of serial transport.
- `max_retries` defaults to `5` and `tick_interval_ms` defaults to `10`.
- The number of non-empty channel topics updates `Config/stimConfig.json` `maxWSS` automatically: 1-3 topics -> `1`, 4-6 topics -> `2`, 7-9 topics -> `3`.
- Leave a channel topic empty in the YAML to disable that channel subscription.
- The default example maps `/dom/index/stimulation_value` to `ch2`.
- Startup reports the selected wrapper file and DLL directory. Bundled wrapper
  code takes precedence over an unrelated pip installation. A different wrapper
  already imported in the process causes a clear restart error, not a hot swap.
- Deliberate external DLL selection remains possible with `WSS_CS_LIB_DIR=/path/to/Cs_Libraries`
  before launch, or the Python node constructor's optional `cs_lib_dir` keyword.
  The node honors it and warns that compatibility is unverified. It does not
  silently fall back, enforce a version/hash allowlist, alter calibration, or
  select another serial port. Load/initialization errors stop startup.
- The existing Core model-capacity limitation remains: `StimWithMode` sizes model
  state by device count rather than channel count. Existing nested model constants
  also retain their historical fallback behavior because Core looks up bare keys.
  Neither behavior is repaired by this compatibility change. Calibration or Core
  behavior corrections require their own review because output can change.
