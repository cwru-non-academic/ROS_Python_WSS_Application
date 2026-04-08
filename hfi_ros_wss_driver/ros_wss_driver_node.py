#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from dataclasses import replace
from datetime import datetime
from pathlib import Path

from rclpy.node import Node
from std_msgs.msg import Float64


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _ensure_wrapper_importable() -> None:
    try:
        import wss_py_wrapper  # noqa: F401

        return
    except ModuleNotFoundError as exc:
        wrapper_src = _repo_root() / "HFI_WSS_Python_Interface" / "src"
        if wrapper_src.is_dir():
            sys.path.insert(0, str(wrapper_src))
            import wss_py_wrapper  # noqa: F401

            return
        raise ModuleNotFoundError(
            "Could not import 'wss_py_wrapper'. Initialize the submodule at "
            "HFI_WSS_Python_Interface and install the wrapper repo, or run this "
            "node from the application checkout with the submodule present."
        ) from exc


_ensure_wrapper_importable()

from wss_py_wrapper import StimulationController, WssConfig


class RosWssDriverNode(Node):
    def __init__(self, test_flag: bool = False, node_name: str = "ros_wss_driver_node"):
        super().__init__(node_name)

        self.declare_parameter("node_name", node_name)
        self.declare_parameter("config_path", str(_repo_root() / "Config"))
        self.declare_parameter("log_path", str(self._default_log_path()))
        self.declare_parameter("serial_port", "")
        self.declare_parameter("test_mode", False)
        self.declare_parameter("max_retries", 5)
        self.declare_parameter("tick_interval_ms", 10)
        for channel in range(1, 10):
            self.declare_parameter(
                f"ch{channel}_topic",
                f"/dom/ch{channel}/stimulation_value",
            )

        self._controller: StimulationController | None = None
        self._subscriptions = []

        if not test_flag:
            self.setup()

    @staticmethod
    def _default_log_path() -> Path:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        return _repo_root() / "logs" / f"wss_{timestamp}.log"

    def setup(self) -> None:
        configured_name = self.get_parameter("node_name").value.strip()
        if configured_name and configured_name != self.get_name():
            self.get_logger().warn(
                "Parameter 'node_name' differs from the launched node name. "
                "ROS2 node names are fixed at construction, so the launched name is used."
            )

        config_path = (
            Path(self.get_parameter("config_path").value).expanduser().resolve()
        )
        log_path = Path(self.get_parameter("log_path").value).expanduser().resolve()
        serial_port = self.get_parameter("serial_port").value.strip()
        test_mode = bool(self.get_parameter("test_mode").value)
        max_retries = int(self.get_parameter("max_retries").value)
        tick_interval_ms = int(self.get_parameter("tick_interval_ms").value)
        configured_topics: list[tuple[int, str]] = []
        for channel in range(1, 10):
            topic_name = self.get_parameter(f"ch{channel}_topic").value.strip()
            if topic_name:
                configured_topics.append((channel, topic_name))

        config_path.mkdir(parents=True, exist_ok=True)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        self._update_max_wss_config(config_path, len(configured_topics))

        config = WssConfig(
            config_path=config_path,
            log_path=log_path,
            cs_lib_dir=_repo_root() / "HFI_WSS_Python_Interface" / "Cs_Libraries",
            test_mode=test_mode,
            max_setup_tries=max(1, max_retries),
            tick_interval_ms=max(1, tick_interval_ms),
        )
        if serial_port:
            config = replace(config, serial_port=serial_port)

        self._controller = StimulationController(config)
        self._controller.Initialize()

        for channel, topic_name in configured_topics:
            subscription = self.create_subscription(
                Float64,
                topic_name,
                self._build_stim_callback(channel, topic_name),
                10,
            )
            self._subscriptions.append(subscription)
            self.get_logger().info(f"Mapped topic '{topic_name}' to ch{channel}.")

        self.get_logger().info(
            "WSS driver ready. "
            f"Config={config_path}, Log={log_path}, Serial={serial_port or 'auto-detect'}, "
            f"TestMode={test_mode}, MaxRetries={config.max_setup_tries}, TickMs={config.tick_interval_ms}, "
            f"MaxWSS={self._max_wss_for_topic_count(len(configured_topics))}"
        )

    @staticmethod
    def _max_wss_for_topic_count(topic_count: int) -> int:
        if topic_count <= 3:
            return 1
        if topic_count <= 6:
            return 2
        return 3

    def _update_max_wss_config(self, config_path: Path, topic_count: int) -> None:
        stim_config_path = config_path / "stimConfig.json"
        if not stim_config_path.is_file():
            self.get_logger().warn(
                f"Could not update maxWSS because '{stim_config_path}' does not exist."
            )
            return

        max_wss = self._max_wss_for_topic_count(topic_count)

        try:
            with stim_config_path.open("r", encoding="ascii") as file:
                stim_config = json.load(file)

            if stim_config.get("maxWSS") == max_wss:
                return

            stim_config["maxWSS"] = max_wss

            with stim_config_path.open("w", encoding="ascii") as file:
                json.dump(stim_config, file, indent=2)
                file.write("\n")
        except Exception as exc:
            self.get_logger().error(
                f"Failed to update '{stim_config_path}' maxWSS to {max_wss}: {exc}"
            )
            raise

    def _build_stim_callback(self, channel: int, topic_name: str):
        channel_name = f"ch{channel}"

        def callback(msg: Float64) -> None:
            if self._controller is None:
                self.get_logger().error("WSS controller is not initialized.")
                return

            value = min(1.0, max(0.0, float(msg.data)))
            if value != float(msg.data):
                self.get_logger().warn(
                    f"Clamped out-of-range stimulation value {msg.data} on '{topic_name}' to {value}."
                )

            try:
                self._controller.StimWithMode(channel_name, value)
            except Exception as exc:
                self.get_logger().error(
                    f"Failed to send stimulation on {channel_name} from '{topic_name}': {exc}"
                )

        return callback

    def shutdown_controller(self) -> None:
        if self._controller is None:
            return
        try:
            self._controller.Shutdown()
        except Exception as exc:
            self.get_logger().error(f"Error during WSS shutdown: {exc}")
        finally:
            self._controller = None

    def destroy_node(self):
        self.shutdown_controller()
        return super().destroy_node()
