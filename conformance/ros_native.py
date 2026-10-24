"""Installed ROS/DDS fixture using a recording managed layer, never a transport."""
import argparse
import json
from pathlib import Path
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
args = parser.parse_args()


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
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps({"schema": "wss-ros-native/v1", "passed": True, "execution": "actual rclpy/DDS, actual wrapper forwarding, managed recording double; no CLR or transport", "channels": sorted({ch for ch, _ in recorder.calls}), "wrapper_file": wss_py_wrapper.__file__, "application_root": str(application_root())}, indent=2))
        node._controller._wss = None
    finally:
        if node is not None:
            # Never leave the managed double installed during real cleanup.
            node._controller._wss = None
            node.destroy_node()
        rclpy.shutdown()
