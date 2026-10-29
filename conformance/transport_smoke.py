"""Check ROS option routing through actual Core constructors; ROS APIs are doubled."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT))
os.environ.setdefault("PYTHONNET_RUNTIME", "coreclr")
from ros_stubs import Node, install

install()
from hfi_ros_wss_driver import ros_wss_driver_node as driver

parser = argparse.ArgumentParser()
parser.add_argument("--payload", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
payload = args.payload.resolve()
checked = []
with TemporaryDirectory(prefix="wss-ros-transport-check-") as directory:
    temp = Path(directory)
    config = temp / "Config"
    config.mkdir()
    (config / "stimConfig.json").write_text(json.dumps({"maxWSS": 3, "firmware": "H03"}))
    cases = [
        ({"serial_port": "COM7" if sys.platform == "win32" else "/dev/ttyWssSmoke"}, "SerialPortTransport"),
        ({"test_mode": True}, "TestModeTransport"), ({"transport": "test"}, "TestModeTransport"),
        ({"conformance_mode": True}, "EmulatedWssTransport"), ({"transport": "conformance"}, "EmulatedWssTransport"),
        ({"transport": "ble", "ble_device_name": "WSS-NO-RADIO"}, "BleNusTransport"),
        ({"transport": "ble", "ble_device_id": "00000000-0000-0000-0000-000000000001"}, "BleNusTransport"),
        ({"transport": "ble", "ble_auto": True}, "BleNusTransport"),
    ]
    for selection, expected in cases:
        Node.overrides = {"config_path": str(config), "log_path": str(temp / "test.log"), **selection}
        # Keep the real node setup/controller factory, but never initialize a
        # physical connection. Construct its selected actual transport below.
        with patch.object(driver.StimulationController, "Initialize"):
            node = driver.RosWssDriverNode(cs_lib_dir=payload)
        transport = None
        try:
            controller = node._controller
            controller._load_dotnet()
            transport = controller._create_transport()
            assert transport.GetType().Name == expected, (selection, str(transport.GetType()))
            assert Path(str(transport.GetType().Assembly.Location)).resolve().is_relative_to(payload)
            checked.append({"parameters": selection, "transport": str(transport.GetType().FullName)})
        finally:
            if transport is not None:
                transport.Dispose()
            node.destroy_node()
    Node.overrides = {}
# Exercise the schema in the actual bundled Core assembly, using disposable copies.
from Wss.CoreModule import CoreConfig, CoreConfigController
with TemporaryDirectory(prefix="wss-address-schema-") as directory:
    address_path = Path(directory) / "stimConfig.json"
    template = json.loads((ROOT / "Config" / "stimConfig.json").read_text())
    defaults = CoreConfig()
    assert int(template["broadcastTarget"], 16) == int(defaults.broadcastTarget, 16)
    assert [int(value, 16) for value in template["wssTargets"]] == [int(value, 16) for value in defaults.wssTargets]
    for label, configuration, expected in (
        ("template", template, (0x8F, [0x81, 0x82, 0x83])),
        ("legacy", {key: value for key, value in template.items() if key not in ("broadcastTarget", "wssTargets")}, (0x8F, [0x81, 0x82, 0x83])),
        ("custom", {**template, "broadcastTarget": "0x8E", "wssTargets": ["0x80", "0x82", "0x83"]}, (0x8E, [0x80, 0x82, 0x83])),
    ):
        address_path.write_text(json.dumps(configuration))
        before = address_path.read_bytes()
        loaded = CoreConfigController(str(address_path))
        assert (int(loaded.BroadcastTarget), [int(value) for value in loaded.WssTargets]) == expected, label
        assert address_path.read_bytes() == before, label

args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({"schema": "wss-ros-transport-selection/v1", "passed": True,
    "constructed": checked, "receiver_config": "template, legacy and custom schemas passed against bundled Core; no user-file migration", "ros_scope": "ROS APIs doubled; no native DDS assertion in this check",
    "serial_auto": "configuration tested separately; construction requires a real port inventory", "physical_io": False}, indent=2))
print("PASS: ROS parameters reach actual Core transport constructors; no physical I/O or native ROS claim.")
