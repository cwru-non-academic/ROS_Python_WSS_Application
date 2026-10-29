# ROS 2 WSS Application

Map ROS 2 `std_msgs/msg/Float64` topics to WSS stimulation channels through the [Python integration library](https://github.com/cwru-non-academic/Python_WSS_Integration_Lib#readme). Shared architecture, configuration, and transport guidance lives in the [WSS documentation hub](https://cwru-non-academic.github.io/WSS_Documentation/).

## Prerequisites and setup

Use a sourced ROS 2 environment with `rclpy`, `std_msgs`, `ament_cmake`, `ament_cmake_python`, `launch_ros`, `ament_index_python`, PyYAML, and `colcon`. The Python interpreter used by ROS also needs `pythonnet` and a compatible .NET runtime of the same architecture. On Linux/macOS select CoreCLR before starting ROS: `export PYTHONNET_RUNTIME=coreclr`.

From your ROS workspace:

```bash
mkdir -p src
cd src
git clone https://github.com/cwru-non-academic/ROS_Python_WSS_Application.git
cd ROS_Python_WSS_Application
git -c 'url.https://github.com/.insteadOf=git@github.com:' submodule update --init --recursive
python3 -m pip install -e HFI_WSS_Python_Interface
cd ../..
colcon build --packages-select hfi_ros_wss_driver --symlink-install
source install/setup.bash
```

The submodule command uses HTTPS for the SSH-style URLs stored in older submodule entries; it needs no global Git configuration change.

Use the same Python environment for `pip`, `colcon`, and the running node. `HFI_WSS_Python_Interface/` is the retained local submodule directory name; the current repository is `Python_WSS_Integration_Lib`. Keep its complete `Cs_Libraries/` directory and platform backend/native assets together.

## First run without hardware

From the ROS workspace root, launch the installed executable with explicit simulation and writable configuration/log paths:

```bash
ros2 run hfi_ros_wss_driver ros_wss_driver.py --ros-args \
  -p test_mode:=true \
  -p config_path:="$PWD/src/ROS_Python_WSS_Application/Config" \
  -p log_path:="$PWD/wss-simulation.log"
```

This command does not open a serial/BLE connection. The default node maps `/dom/ch1/stimulation_value` through `/dom/ch9/stimulation_value` to `ch1` through `ch9`. In another sourced terminal:

```bash
ros2 topic pub --once /dom/ch2/stimulation_value std_msgs/msg/Float64 "{data: 0.0}"
```

Stop the node with Ctrl+C to shut down the controller. The node updates `stimConfig.json` `maxWSS` from the number of nonempty configured topics, so use an app-owned writable config directory.

## Configure a session

Set `ch1_topic` through `ch9_topic` to your publisher topic names; an empty string disables a subscription. Incoming magnitudes are clamped to `[0.0, 1.0]` and passed to `StimWithMode("chN", value)`.

Use a ROS parameter file with a node-name/`ros__parameters` block for `ros2 run ... --ros-args --params-file /absolute/path/session.yaml`, or add individual `-p` overrides. Configuration includes `config_path`, `log_path`, `serial_port`, `test_mode`, `max_retries` (default 5), and `tick_interval_ms` (default 10). Review the shared [configuration reference](https://cwru-non-academic.github.io/WSS_Documentation/apiDocs/conceptual/config-files-reference.html) before using a physical device; select `test_mode:=false` and an explicit `serial_port` for serial operation.

The supplied launch entry point is `ros2 launch hfi_ros_wss_driver launch_ros_wss_driver.launch.py config_file:=session.yaml`. This launcher reads a flat WSS settings YAML from the package's `config/` directory, rather than the ROS parameter-file format above. Set its paths and topic names for your installation before launching; use the explicit simulation command above for the first run.

## Update a checkout

Stop the node, update the application, then run `git submodule sync --recursive` and the same HTTPS submodule update command inside its checkout. Rebuild with `colcon` and source `install/setup.bash` again before restarting. The checked-in submodule pin selects the wrapper and DLL payload together.

For a console without ROS, use the [Python CLI](https://github.com/cwru-non-academic/CLI_Python_WSS_Application#readme).
