"""Check installed ROS DDS callbacks and interrupt cleanup without hardware."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
from unittest.mock import patch

import rclpy
from std_msgs.msg import Float64
from hfi_ros_wss_driver import ros_wss_driver_node as driver
from hfi_ros_wss_driver.runtime import application_root
import wss_py_wrapper

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--projection", type=Path, required=True)
args = parser.parse_args()
# The transfer manifest was hash-bound to the independently validated Windows
# projection. Verify every installed byte in both colcon layouts, including dylib.
from hfi_ros_wss_driver.payload_verification import verify_installed_payload
from ament_index_python.packages import get_package_prefix, get_package_share_directory
share = Path(get_package_share_directory("hfi_ros_wss_driver"))
installed_payload = verify_installed_payload(
    share / "HFI_WSS_Python_Interface" / "Cs_Libraries", args.projection
)

def check_driver_interrupt():
    executable = (Path(get_package_prefix("hfi_ros_wss_driver")) / "lib"
                  / "hfi_ros_wss_driver" / "ros_wss_driver.py")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        config = shutil.copytree(share / "Config", root / "Config")
        log = root / "driver.log"
        with log.open("w") as output, subprocess.Popen(
            [str(executable), "--ros-args", "-p", "transport:=test",
             "-p", f"config_path:={config}", "-p", f"log_path:={root / 'core.log'}",
             "-r", "__node:=wss_interrupt_check"],
            stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
            env={**os.environ, "PYTHONNET_RUNTIME": "coreclr", "PYTHONUNBUFFERED": "1"},
        ) as child:
            try:
                deadline = time.monotonic() + 30
                while child.poll() is None and time.monotonic() < deadline:
                    if "Transport=test, Target=in-memory" in log.read_text():
                        break
                    time.sleep(0.1)
                else:
                    raise AssertionError("Installed driver did not start")
                child.send_signal(signal.SIGINT)
                if child.wait(timeout=10) != 0:
                    raise AssertionError(f"Installed driver exited {child.returncode} on SIGINT")
                if "Traceback" in log.read_text():
                    raise AssertionError("Installed driver logged an exception on SIGINT")
            except (AssertionError, subprocess.TimeoutExpired) as error:
                raise AssertionError(f"{error}\n{log.read_text()}") from error
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=5)
    print("PASS: installed ROS driver handled SIGINT and exited 0")

class Recorder:
    def __init__(self):
        self.calls = []

    def StimWithMode(self, channel, value):
        self.calls.append((channel, value))


with tempfile.TemporaryDirectory() as directory:
    config = Path(directory)
    (config / "stimConfig.json").write_text('{"maxWSS": 3, "firmware": "H03"}')
    rclpy.init(args=["--ros-args", "-p", f"config_path:={directory}", "-p", f"log_path:={config / 'test.log'}"])
    node = None
    try:
        with patch.object(driver.StimulationController, "Initialize"):
            node = driver.RosWssDriverNode()
        assert len(node._channel_subscriptions) == 9
        assert len({id(item) for item in node._channel_subscriptions}) == 9
        recorder = Recorder()
        node._controller._wss = recorder
        publishers = [(ch, node.create_publisher(Float64, f"/dom/ch{ch}/stimulation_value", 10)) for ch in range(1, 10)]
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            for _, publisher in publishers:
                publisher.publish(Float64(data=0.5))
            rclpy.spin_once(node, timeout_sec=0.02)
            if {ch for ch, value in recorder.calls if value == 0.5} == set(range(1, 10)):
                break
        else:
            raise AssertionError(f"Missing DDS channel callbacks: {recorder.calls}")
        assert "clr" not in __import__("sys").modules
        channels = sorted({ch for ch, _ in recorder.calls})
        node._controller._wss = None
    finally:
        if node is not None:
            # Never leave the managed double installed during real cleanup.
            node._controller._wss = None
            node.destroy_node()
        rclpy.shutdown()

check_driver_interrupt()
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({
    "schema": "wss-ros-native/v1",
    "passed": True,
    "execution": "actual rclpy/DDS with managed recording double; installed driver SIGINT with in-memory transport",
    "installed_payload": installed_payload,
    "channels": channels,
    "sigint_exit_code": 0,
    "wrapper_file": wss_py_wrapper.__file__,
    "application_root": str(application_root()),
}, indent=2))
