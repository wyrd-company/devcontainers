#!/usr/bin/env python3
# relationships:
#   implements: t3code-server
"""Read native launcher state and select a runtime while the service is stopped."""

import json
import os
from pathlib import Path
import re
import sys
import tempfile


VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")


def exact(value):
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise ValueError("Invalid runtime version")
    return value


def write(path, contents):
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix=".service-write-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(contents)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(temp).unlink(missing_ok=True)


def state(runtime):
    path = runtime / "service-state.json"
    if not path.exists():
        return None
    value = json.loads(path.read_text())
    if not isinstance(value, dict) or value.get("protocol") != 3:
        raise ValueError("Unsupported service-state protocol")
    exact(value.get("activeVersion"))
    update = value.get("update")
    if update is not None:
        if not isinstance(update, dict) or update.get("status") not in ("pending", "committed", "rolled-back", "failed"):
            raise ValueError("Invalid native update state")
        previous, target = exact(update.get("fromVersion")), exact(update.get("targetVersion"))
        if not isinstance(update.get("id"), str) or not update["id"].strip():
            raise ValueError("Invalid native update ID")
        expected = target if update["status"] == "committed" else previous
        if value["activeVersion"] != expected:
            raise ValueError("Native update and active version disagree")
    return value


def main():
    runtime = Path(sys.argv[1])
    command = sys.argv[2]
    native = state(runtime)
    if command == "selected":
        print(exact(native["activeVersion"] if native else (runtime / "selected-version").read_text().strip()))
    elif command == "pending":
        sys.exit(0 if native and native.get("update", {}).get("status") == "pending" else 1)
    elif command == "select":
        # The installer or stopped-service maintenance path is the only caller.
        version, protocol = exact(sys.argv[3]), sys.argv[4]
        if native and native.get("update", {}).get("status") == "pending":
            raise ValueError("A native update is pending; let the launcher recover it first")
        if protocol == "3":
            launcher = runtime / "service-launcher"
            temp = runtime / ".service-launcher-next"
            temp.unlink(missing_ok=True)
            temp.symlink_to(Path("versions") / version / "t3")
            os.replace(temp, launcher)
            # Native pruning follows recorded symlinks, including this fixed launcher.
            launchers = runtime / "launchers"
            paths = launchers.read_text().splitlines() if launchers.exists() else []
            if str(launcher) not in paths:
                write(launchers, "\n".join([*paths, str(launcher)]) + "\n")
            write(runtime / "service-state.json", json.dumps({"protocol": 3, "activeVersion": version}) + "\n")
            (runtime / "selected-version").unlink(missing_ok=True)
        else:
            write(runtime / "selected-version", version + "\n")
            (runtime / "service-state.json").unlink(missing_ok=True)
            (runtime / "service-launcher").unlink(missing_ok=True)
    else:
        raise ValueError("Unknown service-state command")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(f"[t3code-runtime] ERROR: {error}")
