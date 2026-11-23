# HFI_ROS_WSS_Driver
A repository that maps incoming ROS2 stimulation magnitudes to the WSS stimulator.

## First stimulation

### Install and build on Ubuntu 22.04

This walkthrough uses ROS 2 Humble on Ubuntu 22.04 x64. Install [ROS 2 Humble ROS Base using the Ubuntu packages](https://docs.ros.org/en/humble/Installation/Ubuntu-Install-Debs.html). Install the [.NET runtime](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu) for the same architecture as Python. The WSS platform checks use .NET 9 with CoreCLR. Confirm that `dotnet --list-runtimes` lists `Microsoft.NETCore.App` 9.x.

In Bash:

```bash
sudo apt update
sudo apt install git python3-pip python3-yaml python3-colcon-common-extensions \
  ros-humble-ament-cmake-python ros-humble-launch-ros ros-humble-ros2launch
source /opt/ros/humble/setup.bash
git clone --recurse-submodules https://github.com/cwru-non-academic/ROS_Python_WSS_Application.git
cd ROS_Python_WSS_Application
python3 -m pip install --user -r requirements.txt
colcon build --packages-select hfi_ros_wss_driver --symlink-install
source install/setup.bash
```

If the wrapper directory is empty, run `git submodule update --init --recursive` before building. The build installs the pinned wrapper and its DLLs. The node uses the system ROS Python, including the `pythonnet` you just installed for that interpreter.

### Prepare a portable launch config

Follow the [hardware overview](https://cwru-non-academic.github.io/WSS_Documentation/hardwareDocs/wsshardware.html) for the physical setup and the [bench verification handoff](https://github.com/cwru-non-academic/WSS_Documentation/blob/main/apiDocs/conceptual/start-here-using-an-application.md#bench-verification) for the approved profile and measurement procedure. Use a bench setup with no person connected.

From the repo root, copy the three example JSONs to a writable directory and apply the bench profile there:

```bash
mkdir -p "$PWD/Config-bench" "$PWD/logs"
cp Config/*.json "$PWD/Config-bench/"
printf 'config_path: %s\nlog_path: %s\n' "$PWD/Config-bench" "$PWD/logs/wss-bench.log"
```

The example `stimConfig.json` uses H03 and first receiver `0x81`. Set its firmware and receiver address to match the bench device. The shipped `stimParams.json` has example calibration on `ch1` and zeroed calibration on `ch2` and `ch3`. Use the approved calibration and paired model config for `ch1`. The node updates `maxWSS` based on the number of enabled topics, with up to three topics selecting one device. It writes this value into the active `stimConfig.json`, so use the writable copy.

Create `wss-bench.yaml` in the repo root with the following entries. Replace the first two paths with the full paths printed above. Replace the serial port with the path of the intended WSS device. See [Linux serial dependencies and permissions](https://github.com/cwru-non-academic/WSSCore#linux-serial-setup) if the port is unavailable.

```yaml
config_path: '/absolute/path/to/ROS_Python_WSS_Application/Config-bench'
log_path: '/absolute/path/to/ROS_Python_WSS_Application/logs/wss-bench.log'
transport: serial
serial_port: '/dev/ttyUSB0'
ch1_topic: /dom/thumb/stimulation_value
ch2_topic: ''
ch3_topic: ''
ch4_topic: ''
ch5_topic: ''
ch6_topic: ''
ch7_topic: ''
ch8_topic: ''
ch9_topic: ''
```

The launch file accepts this flat YAML through `config_file`. Always pass the absolute path to your YAML. The installed example YAML contains paths specific to another machine. For BLE, change `transport` to `ble`, remove `serial_port`, and add `ble_device_name` with the exact advertised NUS name or `ble_device_id` with its local identifier.

### Launch, publish, and stop

1. In the first terminal with both ROS environments sourced, run:

   ```bash
   export PYTHONNET_RUNTIME=coreclr
   ros2 launch hfi_ros_wss_driver launch_ros_wss_driver.launch.py config_file:="$PWD/wss-bench.yaml"
   ```

   Check that the node reports the expected transport, config, log, and topic-to-channel mapping. Setup continues after the initialization banner and starts streaming automatically. Check the Core log for an acknowledged `StartStim` for the device before publishing. Diagnose setup retries or missing acknowledgments in that log.

2. In a second Bash terminal, change to the same repo root and source both environments. Inspect the subscriber before sending a message:

   ```bash
   source /opt/ros/humble/setup.bash
   source install/setup.bash
   ros2 topic info /dom/thumb/stimulation_value
   read -r -p 'Bench-profile normalized magnitude: ' magnitude
   ros2 topic pub --once /dom/thumb/stimulation_value std_msgs/msg/Float64 "{data: $magnitude}"
   ```

   Use the normalized input specified by your bench profile. The driver clamps incoming values to `[0.0, 1.0]` before applying the active model and calibration to `ch1`. A subscription or successful publish verifies ROS delivery prerequisites. Confirm the actual output with the bench procedure.

3. Stop any publishers and press **Ctrl+C** in the launch terminal to tear down the driver and its WSS controller. Verify output has ceased. Restart the driver after changing transports, receiver addresses, or configuration paths.

For a hardware-free rehearsal, copy the YAML, set `transport: test`, and remove `serial_port` and any BLE selectors. Use a disposable JSON directory and a separate log. The `conformance` transport also keeps the ROS node running with the selected profiles and topics.

## Updating an existing checkout

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
- The number of non-empty channel topics updates `Config/stimConfig.json` `maxWSS` automatically: 0-3 topics -> `1`, 4-6 topics -> `2`, 7-9 topics -> `3`.
- Leave a channel topic empty in the YAML to disable that channel subscription.
- The shipped YAML maps `/dom/index/stimulation_value` to `ch2`. The first-run YAML uses `/dom/thumb/stimulation_value` with `ch1`.
- Startup reports the selected wrapper file and DLL directory. Bundled wrapper
  code takes precedence over an unrelated pip installation. A different wrapper
  already imported in the process causes a clear restart error, not a hot swap.
- Deliberate external DLL selection remains possible with `WSS_CS_LIB_DIR=/path/to/Cs_Libraries`
  before launch, or the Python node constructor's optional `cs_lib_dir` keyword.
  The node honors it and warns that compatibility is unverified. It does not
  silently fall back, enforce a version/hash allowlist, alter calibration, or
  select another serial port. Load/initialization errors stop startup.


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
