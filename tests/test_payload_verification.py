"""Reject payload loss/corruption across installed ROS layouts."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from hfi_ros_wss_driver.payload_verification import verify_installed_payload


class InstalledPayloadTests(unittest.TestCase):
    def test_complete_payload_and_rejections(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "payload"
            root.mkdir()
            backend = root / "backends/macos/libwss_macos_ble.dylib"
            backend.parent.mkdir(parents=True)
            backend.write_bytes(b"native bytes")
            projection = base / "projection.json"
            projection.write_text(json.dumps({"schema": "wss-python-projection/v1",
                "projection_sha256": "test digest", "files": [{
                    "source": backend.relative_to(root).as_posix(),
                    "sha256": hashlib.sha256(backend.read_bytes()).hexdigest()}]}))
            self.assertEqual(verify_installed_payload(root, projection)["verified_files"], 1)
            backend.write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                verify_installed_payload(root, projection)
            backend.unlink()
            with self.assertRaisesRegex(ValueError, "inventory differs"):
                verify_installed_payload(root, projection)
            backend.write_bytes(b"native bytes")
            (root / "unexpected.dll").write_bytes(b"extra")
            with self.assertRaisesRegex(ValueError, "inventory differs"):
                verify_installed_payload(root, projection)
