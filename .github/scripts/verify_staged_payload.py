"""Verify every downloaded payload byte against the Windows-validated manifest."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("root", type=Path)
parser.add_argument("manifest_sha256")
args = parser.parse_args()
manifest = args.root / "projection.json"
if hashlib.sha256(manifest.read_bytes()).hexdigest() != args.manifest_sha256:
    raise SystemExit("Projection record differs from the Windows validation output")
record = json.loads(manifest.read_text(encoding="utf-8-sig"))
if record["schema"] != "wss-python-projection/v1":
    raise SystemExit("Unexpected projection schema")
files = record["files"]
names = [entry["source"] for entry in files]
actual = {item.relative_to(args.root / "payload").as_posix() for item in (args.root / "payload").rglob("*") if item.is_file()}
if len(names) != len(set(names)) or actual != set(names):
    raise SystemExit("Downloaded payload inventory differs")
for entry in files:
    path = Path(entry["source"])
    if path.is_absolute() or ".." in path.parts:
        raise SystemExit("Unsafe payload path")
    if hashlib.sha256((args.root / "payload" / path).read_bytes()).hexdigest() != entry["sha256"]:
        raise SystemExit(f"Payload hash mismatch: {path}")
print(f"Verified {len(files)} payload files and the exact cross-job projection record")
