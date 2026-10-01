#!/usr/bin/env python3
"""Select the CI test targets affected by a change.

Usage: ci-changes.py --all
       ci-changes.py <base-sha> <head-sha>

Prints `targets=<JSON array>` for $GITHUB_OUTPUT. Targets are Feature ids plus
`base-image` and `template`. A change to shared test infrastructure, the base
image, or a path this script does not recognize selects every target, as does
a base commit that is missing or not in the checked-out history.
"""

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
FEATURES_DIR = ROOT / "src/features"

# Paths whose change can affect any test.
SHARED = (
    ".github/workflows/ci.yml",
    "scripts/ci-changes.py",
    "scripts/test-features.sh",
    "scripts/build-base-image.sh",
    "scripts/check-sudo-no-all.sh",
    "test/check-sudo-no-all/",
    "src/images/",
)

# Paths that no test reads.
IGNORED = (
    ".github/",
    "LICENSES/",
    "scripts/cleanup-ghcr-images.sh",
)

# Runtime scripts whose name is not a Feature id: scripts/test-<name>-runtime.sh.
RUNTIME_SCRIPTS = {
    "codex": ["codex-cli"],
    "codex-caddy": ["codex-cli", "caddy"],
    "codex-exec": ["codex-cli"],
    "openbao-secret-files": ["openbao-agent"],
    "t3code": ["t3code-server"],
}


def all_features():
    return sorted(path.name for path in FEATURES_DIR.iterdir() if (path / "devcontainer-feature.json").is_file())


def all_targets():
    return all_features() + ["base-image", "template"]


def targets_for(path, features):
    """Return the targets a changed path selects, or None for every target."""
    if path.startswith(SHARED):
        return None
    for prefix in ("src/features/", "test/features/"):
        if path.startswith(prefix):
            name = path[len(prefix):].split("/", 1)[0]
            return [name] if name in features else None
    if path.startswith("src/templates/"):
        return ["template"]
    if path == "scripts/test-moby-opt-in.sh":
        return ["base-image"]
    match = re.fullmatch(r"scripts/test-(.+)-runtime\.sh", path)
    if match:
        name = match.group(1)
        if name in features:
            return [name]
        return RUNTIME_SCRIPTS.get(name)
    if path.startswith(IGNORED) or "/" not in path:
        return []
    return None


def add_dependents(selected, features):
    """Add Features whose metadata names a selected Feature, transitively."""
    metadata = {name: (FEATURES_DIR / name / "devcontainer-feature.json").read_text() for name in features}
    pending = [name for name in selected if name in features]
    while pending:
        dependency = pending.pop()
        reference = re.compile(r"wyrd-company/devcontainers/" + re.escape(dependency) + r'(?=[:"])')
        for name, text in metadata.items():
            if name not in selected and reference.search(text):
                selected.add(name)
                pending.append(name)
    return selected


def changed_paths(base, head):
    if not base or set(base) == {"0"}:
        return None
    result = subprocess.run(
        ["git", "diff", "--name-only", base, head],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        print(f"Unable to diff {base}..{head}; selecting every target.", file=sys.stderr)
        return None
    return [line for line in result.stdout.splitlines() if line]


def select(paths):
    if paths is None:
        return all_targets()
    features = set(all_features())
    selected = set()
    for path in paths:
        targets = targets_for(path, features)
        if targets is None:
            print(f"{path} affects every target.", file=sys.stderr)
            return all_targets()
        selected.update(targets)
    return sorted(add_dependents(selected, features))


def main(argv):
    if argv == ["--all"]:
        targets = all_targets()
    elif len(argv) == 2:
        targets = select(changed_paths(argv[0], argv[1]))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    print(f"Selected targets: {', '.join(targets) or '(none)'}", file=sys.stderr)
    print("targets=" + json.dumps(targets, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
