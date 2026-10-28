"""ROS-facing baseline captured before upgrading wrapper 60f29a8.

Use the production Python wrapper's StimWithMode forwarding with a recording
managed-layer double. No CLR, transport, ROS node process, or hardware is started.
"""
import importlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ros_stubs import Float64, Node, install

install()
driver = importlib.import_module("hfi_ros_wss_driver.ros_wss_driver_node")


class ManagedLayer:
    def __init__(self):
        self.calls = []

    def StimWithMode(self, channel, value):
        self.calls.append((channel, value))


class RosContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "Config"
        self.config.mkdir()
        self.original = {"maxWSS": 3, "firmware": "H03", "calibration_marker": [7, 8]}
        (self.config / "stimConfig.json").write_text(json.dumps(self.original), encoding="ascii")
        self.params = b'{"stim":{"ch":{"1":{"minPW":20,"maxPW":100}}}}'
        (self.config / "stimParams.json").write_bytes(self.params)
        Node.overrides = {"config_path": str(self.config), "log_path": str(self.root / "logs" / "test.log")}
        self.addCleanup(setattr, Node, "overrides", {})

    def construct(self):
        with patch.object(driver.StimulationController, "Initialize") as initialize:
            node = driver.RosWssDriverNode()
        self.assertEqual(initialize.call_count, 1)
        self.addCleanup(node.destroy_node)
        return node

    def test_parameter_defaults_and_topic_contract(self):
        node = self.construct()
        self.assertEqual(set(node.parameters), {"node_name", "config_path", "log_path", "serial_port", "test_mode", "max_retries", "tick_interval_ms"} | {f"ch{i}_topic" for i in range(1, 10)})
        self.assertEqual(node.parameters["node_name"], "ros_wss_driver_node")
        for key, value in {"serial_port": "", "test_mode": False, "max_retries": 5, "tick_interval_ms": 10}.items():
            self.assertEqual(node.parameters[key], value)
        self.assertEqual([(kind, topic, depth) for kind, topic, _, depth in node.subscriptions], [(Float64, f"/dom/ch{i}/stimulation_value", 10) for i in range(1, 10)])

    def test_all_callbacks_enter_actual_wrapper_stim_with_mode(self):
        node = self.construct()
        managed = ManagedLayer()
        node._controller._wss = managed
        for _, _, callback, _ in node.subscriptions:
            callback(Float64(0.5))
        self.assertEqual(managed.calls, [(i, 0.5) for i in range(1, 10)])
        node._controller._wss = None

    def test_bounds_and_nonfinite_inputs_preserve_existing_clamp(self):
        node = self.construct()
        managed = ManagedLayer()
        node._controller._wss = managed
        callback = node.subscriptions[0][2]
        for value in (-1.0, 0.0, 0.5, 1.0, 2.0, float("-inf"), float("inf"), float("nan")):
            callback(Float64(value))
        self.assertEqual([value for _, value in managed.calls], [0.0, 0.0, 0.5, 1.0, 1.0, 0.0, 1.0, 0.0])
        node._controller._wss = None

    def test_disabled_topics_keep_channel_numbers_and_custom_names(self):
        Node.overrides.update({f"ch{i}_topic": "" for i in range(1, 10)})
        Node.overrides["ch2_topic"] = "/dom/index/stimulation_value"
        node = self.construct()
        self.assertEqual([(topic, depth) for _, topic, _, depth in node.subscriptions], [("/dom/index/stimulation_value", 10)])
        managed = ManagedLayer()
        node._controller._wss = managed
        node.subscriptions[0][2](Float64(0.25))
        self.assertEqual(managed.calls, [(2, 0.25)])
        node._controller._wss = None

    def test_config_calibration_and_user_paths_are_preserved(self):
        node = self.construct()
        self.assertEqual(json.loads((self.config / "stimConfig.json").read_text()), self.original)
        self.assertEqual((self.config / "stimParams.json").read_bytes(), self.params)
        self.assertEqual(node._controller._config.config_path, self.config.resolve())
        self.assertEqual(node._controller._config.log_path, (self.root / "logs" / "test.log").resolve())

    def test_device_count_retains_established_topic_count_rule(self):
        self.assertEqual([driver.RosWssDriverNode._max_wss_for_topic_count(i) for i in range(10)], [1, 1, 1, 1, 2, 2, 2, 3, 3, 3])
        Node.overrides.update({f"ch{i}_topic": "" for i in range(1, 10)})
        Node.overrides["ch9_topic"] = "/sparse"
        self.construct()
        self.assertEqual(json.loads((self.config / "stimConfig.json").read_text()), {**self.original, "maxWSS": 1})

    def test_retry_tick_serial_and_test_transport_settings(self):
        Node.overrides.update(serial_port="/dev/example", test_mode=True, max_retries=0, tick_interval_ms=-10)
        node = self.construct()
        config = node._controller._config
        self.assertEqual((config.serial_port, config.test_mode, config.max_setup_tries, config.tick_interval_ms), ("/dev/example", True, 1, 1))

    def test_callback_failure_is_logged_without_changing_subscription(self):
        node = self.construct()
        with patch.object(node._controller, "StimWithMode", side_effect=RuntimeError("fixture failure")):
            node.subscriptions[0][2](Float64(0.5))
        self.assertTrue(any(level == "error" and "fixture failure" in message for level, message in node.logger.messages))
        self.assertEqual(len(node.subscriptions), 9)

    def test_shutdown_runs_once_even_when_destroyed_twice(self):
        node = self.construct()
        with patch.object(node._controller, "Shutdown") as shutdown:
            node.destroy_node()
            node.destroy_node()
        self.assertEqual(shutdown.call_count, 1)
        self.assertIsNone(node._controller)

    def test_shutdown_failure_is_logged_and_controller_reference_cleared(self):
        node = self.construct()
        with patch.object(node._controller, "Shutdown", side_effect=RuntimeError("shutdown fixture")):
            node.destroy_node()
        self.assertIsNone(node._controller)
        self.assertTrue(any("shutdown fixture" in message for _, message in node.logger.messages))

    def test_external_dll_path_warns_and_is_not_substituted(self):
        external = self.root / "deliberately-missing-external"
        with patch.object(driver.StimulationController, "Initialize"):
            node = driver.RosWssDriverNode(cs_lib_dir=external)
        self.addCleanup(node.destroy_node)
        self.assertEqual(node._controller._config.cs_lib_dir, external.resolve())
        self.assertTrue(any(level == "warn" and "unverified" in message and str(external.resolve()) in message for level, message in node.logger.messages))
        self.assertTrue(any(level == "info" and "wrapper=" in message and "DLLs=" in message for level, message in node.logger.messages))

    def test_initialization_failure_cleans_up_and_propagates(self):
        with patch.object(driver.StimulationController, "Initialize", side_effect=RuntimeError("init fixture")), patch.object(driver.StimulationController, "Shutdown") as shutdown:
            with self.assertRaisesRegex(RuntimeError, "init fixture"):
                driver.RosWssDriverNode()
        self.assertEqual(shutdown.call_count, 1)

    def test_entrypoint_shuts_down_ros_after_construction_failure(self):
        import importlib.util
        import sys
        script = Path(__file__).resolve().parents[1] / "scripts" / "ros_wss_driver.py"
        spec = importlib.util.spec_from_file_location("entrypoint_fixture", script)
        entrypoint = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(entrypoint)
        ros = sys.modules["rclpy"]
        with patch.object(ros, "init", create=True), patch.object(ros, "shutdown", create=True) as shutdown, patch.object(entrypoint, "RosWssDriverNode", side_effect=RuntimeError("init fixture")):
            with self.assertRaisesRegex(RuntimeError, "init fixture"):
                entrypoint.main()
        shutdown.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
