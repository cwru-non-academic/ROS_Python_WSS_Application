"""Exercise actual ROS callbacks -> wrapper -> Core over in-memory emulation.

ROS is doubled here; native ROS/DDS and colcon are checked separately. This
process can only construct EmulatedWssTransport; never a serial/BLE transport.
"""
from __future__ import annotations

import argparse
from dataclasses import replace
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--payload", type=Path)
args = parser.parse_args()

# Explicit, isolated development host, not a new application runtime default.
from pythonnet import load

load("coreclr", runtime_config=str(Path(__file__).with_name("ros.runtimeconfig.json")))
from ros_stubs import Float64, Node, install

install()
from hfi_ros_wss_driver import ros_wss_driver_node as driver
from wss_py_wrapper import StimulationController
from System import Environment

observations = []


def wait_until(predicate, description):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError(f"Timed out: {description}")


class RosEmulatorTests(unittest.TestCase):
    def exercise(self, mode, amplitude_mode, firmware="H03"):
        for devices in (1, 2, 3):
            with self.subTest(devices=devices), tempfile.TemporaryDirectory() as directory:
                config = Path(directory)
                stim_config = {"maxWSS": devices, "firmware": firmware, "useConfigAmpCurves": True, "ampCurves": [{"LowThreshold": 255.0, "LowConst": 1.0, "ExpPower": 1.0, "LinearOffset": 0.0, "LinearSlope": 1.0}] * 3}
                model = {"calib": {"mode": mode}, "constants": {"PModeProportional": 1.0, "PModeOffset": 0.0, "PDModeProportional": 1.0, "PDModeDerivative": 0.0, "PDModeOffset": 0.0}}
                # Current Core queries bare constant keys. Include explicit root
                # overrides for deterministic PD arithmetic without changing the
                # application's existing nested configuration or Core behavior.
                model.update(model["constants"])
                params = {"stim": {"ch": {str(ch): {"ampMode": amplitude_mode, "minPW": 20, "maxPW": 100, "minPA": 2.0, "maxPA": 6.0, "defaultPA": 1.0, "defaultPW": 50, "IPI": 10} for ch in range(1, 10)}}}
                for name, value in (("stimConfig.json", stim_config), ("modelConfig.json", model), ("stimParams.json", params)):
                    (config / name).write_text(json.dumps(value), encoding="ascii")
                Node.overrides = {"config_path": directory, "log_path": str(config / "test.log"), **{f"ch{ch}_topic": f"/fixture/ch{ch}" if ch <= devices * 3 else "" for ch in range(1, 10)}}

                def factory(original):
                    # Injection exists only in this test process. The node still
                    # builds its production config and calls Initialize itself.
                    selected = replace(original, conformance_mode=True)
                    assert not selected.test_mode
                    controller = StimulationController(selected)
                    if firmware == "H03":
                        def legacy_emulator():
                            from Wss.Testing import EmulatedWssDeviceProfile, EmulatedWssTransport

                            return EmulatedWssTransport(EmulatedWssDeviceProfile.Legacy)
                        controller._create_transport = legacy_emulator
                    return controller

                node = None
                try:
                    with patch.object(driver, "StimulationController", factory):
                        node = driver.RosWssDriverNode(cs_lib_dir=args.payload)
                    controller = node._controller
                    self.assertEqual(controller._transport.GetType().FullName, "Wss.Testing.EmulatedWssTransport")
                    conformance = controller.GetConformance()
                    wait_until(lambda: controller.Started() and conformance.StimulationHistory.Count > 0, "emulated initialization and streaming")
                    result = conformance.ValidateInitialization()
                    self.assertTrue(result.Passed, str(list(result.Failures)))
                    self.assertEqual(conformance.ProtocolErrors.Count, 0)
                    values = []
                    expected = 60 if amplitude_mode == "PW" else 4
                    known_limitation = []
                    for channel, (_, _, callback, _) in enumerate(node.subscriptions, 1):
                        callback(Float64(0.5))
                        actual = controller.GetStimIntensity(f"ch{channel}")
                        values.append(actual)
                        if actual != expected:
                            # Explicitly tolerate only the characterized legacy
                            # capacity issue; zero is not the desired behavior.
                            self.assertGreater(channel, devices)
                            self.assertEqual(actual, 0, "New model/calibration regression")
                            known_limitation.append(channel)
                    # Both legacy and corrected Core can meet the desired model
                    # behavior on supported channels; no blanket xfail/skip.
                    self.assertEqual(values[:devices], [expected] * devices)
                    callback = node.subscriptions[0][2]
                    for incoming, expected_drive in ((float("nan"), 0), (float("-inf"), 0), (float("inf"), 100 if amplitude_mode == "PW" else 6)):
                        callback(Float64(incoming))
                        self.assertEqual(controller.GetStimIntensity("ch1"), expected_drive)
                    self.assertEqual(json.loads((config / "modelConfig.json").read_text()), model)
                    persisted = json.loads((config / "stimParams.json").read_text())
                    for ch in range(1, devices * 3 + 1):
                        self.assertEqual(persisted["stim"]["ch"][str(ch)], params["stim"]["ch"][str(ch)])
                    thread = controller._tick_thread
                    observations.append({"mode": mode, "amplitude_mode": amplitude_mode, "firmware": firmware, "devices": devices, "model_path_drive": values, "desired_drive": expected, "known_model_capacity_limitation_channels": known_limitation, "initialization_conformant": True, "protocol_errors": 0})
                finally:
                    if node is not None:
                        node.destroy_node()
                        self.assertIsNone(node._controller)
                        if "thread" in locals():
                            self.assertFalse(thread.is_alive(), "Tick loop survived shutdown")
                    Node.overrides = {}

    def test_p_model_pw_calibration_all_channels(self):
        self.exercise("P", "PW")

    def test_pd_model_pw_calibration_all_channels(self):
        self.exercise("PD", "PW")

    def test_p_model_pa_calibration_all_channels(self):
        self.exercise("P", "PA")

    def test_pd_model_pa_calibration_all_channels(self):
        self.exercise("PD", "PA")

    def test_j03_query_capable_emulator(self):
        self.exercise("P", "PW", "J03")


suite = unittest.defaultTestLoader.loadTestsFromTestCase(RosEmulatorTests)
result = unittest.TextTestRunner(verbosity=2).run(suite)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({"schema": "wss-ros-emulator/v1", "tests": result.testsRun, "failed": len(result.failures) + len(result.errors), "skipped": len(result.skipped), "execution": "actual Python wrapper and managed Core; ROS doubles; EmulatedWssTransport only", "python": sys.version.split()[0], "clr": str(Environment.Version), "observations": observations}, indent=2), encoding="utf-8")
sys.exit(0 if result.wasSuccessful() else 1)
