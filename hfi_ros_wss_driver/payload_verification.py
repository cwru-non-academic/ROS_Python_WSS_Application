"""Verify installed payload bytes against a separately attested CI projection."""
import hashlib
import json
from pathlib import Path


def verify_installed_payload(root: Path, projection: Path) -> dict:
    """Require the exact inventory and hashes; never load a backend or CLR."""
    content = projection.read_bytes()
    record = json.loads(content.decode("utf-8-sig"))
    if record.get("schema") != "wss-python-projection/v1":
        raise ValueError("Unexpected projection schema")
    entries = record["files"]
    names = [entry["source"] for entry in entries]
    actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
    if not names or len(names) != len(set(names)) or actual != set(names):
        raise ValueError("Installed payload inventory differs from the attested projection")
    for entry in entries:
        path = Path(entry["source"])
        if path.is_absolute() or ".." in path.parts or "\\" in entry["source"]:
            raise ValueError("Unsafe payload path")
        if hashlib.sha256((root / path).read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"Installed payload hash mismatch: {path}")
    return {"projection_record_sha256": hashlib.sha256(content).hexdigest(),
            "projection_sha256": record["projection_sha256"], "verified_files": len(entries)}
