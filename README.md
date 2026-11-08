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
   - the transport (`serial`, `ble`, `test`, or `conformance`) and serial port
   - explicit BLE selection by device name, device ID, or auto-selection
   - whether to use the wrapper test or conformance transport
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

Transport parameters are additive; existing YAML, topic names and publishers
continue to work. `transport` defaults to `serial`. For BLE set `transport: ble`
and one of `ble_device_name`, `ble_device_id`, or `ble_auto: true`. Empty BLE
selectors are rejected rather than silently scanning. BLE cannot be combined
with `serial_port`, `test_mode`, or `conformance_mode`.

`transport: test` and `transport: conformance` select Core's in-memory transports;
`test_mode: true` remains supported and `conformance_mode: true` is an equivalent
explicit flag. Unlike the CLI one-shot diagnostic, the ROS node remains running
with the application's configuration and topics in these modes. Use a suitable
WSS configuration for the emulated firmware. Conflicting simulated modes are
rejected before configuration files are changed or a controller is initialized.

The shared wrapper selects each OS's BLE backend, including the macOS managed
backend and paired native dylib, without a separate ROS BLE implementation.
Use `PYTHONNET_RUNTIME=coreclr` with a compatible installed CLR where needed.
This prepares the application transport path on macOS; native ROS Humble support
is tested only on Ubuntu 22.04. macOS platform checks double the ROS APIs and
exercise actual Core constructors, with no radio discovery or connection.

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
Separate Windows, Ubuntu and macOS CPython 3.12 / pythonnet 3.0.5 / .NET 9
platform jobs test application contracts and the actual wrapper/Core model path
with Core's in-memory emulator, plus runtime/backend loading. Their ROS APIs are
doubled; native ROS coverage remains the separate Ubuntu/Humble job. The macOS
aggregate requires native Intel and Apple Silicon lanes. See
[tests/BASELINE.md](tests/BASELINE.md) and [.github/ROS_COMPATIBILITY.md](.github/ROS_COMPATIBILITY.md).
These are development checks, not certification of every ROS distro or hardware.

The separate `ROS general conformance` Windows job executes the canonical
NUnit corpus selected by the verified payload capability profile through the
same controller factory used by ROS node setup, preserving that profile's
canonical cases and assertion expressions. It requires the single-device stage
for every supported profile and the additional multi-device stage for
`layered-v1`. Its profile-specific canonical evidence, separate model report
and both native layout reports form the complete source-bound evidence set.
Normal CI evidence is not candidate approval: automatic promotion additionally
requires the reviewed v2 wrapper/CLI/ROS proof and a fresh preflight of the
actual merged wrapper.
The three OS checks are named `ROS platform compatibility (Windows)`,
`ROS platform compatibility (Ubuntu)` and `ROS platform compatibility (macOS)`.
`ROS-specific compatibility (Humble)` retains the real colcon/DDS checks.
The declared macOS BLE payload is checked through the actual wrapper/backend
loading path, including BLE name/ID/auto routing. Missing declared backend files
fail the check; green platform checks do not claim physical BLE or native ROS
support on Windows/macOS. `ROS general conformance`
also verifies all suites and the existing promotion evidence format, so ordinary
PRs have five acceptance checks. `Stage verified ROS inputs` is a staging helper.
The unchanged candidate preflight retains its `ROS compatibility` acceptance name.

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

## Device addresses and setup diagnostics

`Config/stimConfig.json` exposes Core's receiver-address settings:
`broadcastTarget` defaults to `"0x8F"`, and `wssTargets` defaults to
`["0x81", "0x82", "0x83"]` for logical Wss1, Wss2 and Wss3. These are receiver
addresses, not the host sender byte. Set the targets for your actual device
configuration (for example, an installation may need `"0x80"` for Wss1).
Existing configurations without these fields use Core's historical defaults;
these template changes do not rewrite existing user configuration. Core keeps
its existing normalization behavior for invalid address values.
Keep the firmware and calibration values appropriate to your hardware.

After changing receiver addresses, stop and restart the ROS driver so Core
constructs a new address map. The driver reads `config_path` during startup and
does not expose a reload command or ROS reload service. The pinned Python
wrapper provides `LoadCoreConfigFile()` and `LoadParamsJson()` for callers using
its API directly; the ROS driver does not call these methods.
Setup continues asynchronously after controller initialization. An initialized
application or an advancing tick loop does not establish that a device is ready.
Core setup and tick errors are recorded in the configured log file; check the
reported absolute config and log paths when diagnosing connection failures.

When the retained dependency payload is legacy and does not declare macOS BLE,
the platform probe asserts that explicit BLE selection is rejected and reports
it as unsupported. It does not count that as BLE construction or runtime proof.
A declared macOS backend missing either its managed DLL or native bridge always
fails; file absence alone never establishes legacy capability.
