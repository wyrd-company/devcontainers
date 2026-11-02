#!/usr/bin/env python3
"""Select the CI test targets affected by a change.

Usage: ci-changes.py --all
       ci-changes.py <base-sha> <head-sha>

Install YAML support with `python3 -m pip install -r scripts/ci-requirements.txt`.
Mapped CI job edits select their owners; workflow-wide or unmapped edits select
every target.

Prints `targets=<JSON array>` and `images=<true|false>` for $GITHUB_OUTPUT.
Targets are Feature ids plus `base-image` and `template`. A change to shared
test infrastructure, the base image, or a path this script does not recognize
selects every target, as does a base commit that is missing or not in the
checked-out history.

`images` tells the image workflow whether to publish the base image. It is true
when the image sources or the image workflow changed, or when the change cannot
be determined.
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
    "scripts/ci-changes.py",
    "scripts/ci-requirements.txt",
    "test/ci-changes/",
    "scripts/test-features.sh",
    "scripts/build-base-image.sh",
    "scripts/check-sudo-no-all.sh",
    "test/check-sudo-no-all/",
    "src/images/",
)

# Paths that no test reads.
IGNORED = (
    ".github/",
    ".intentional/",
    "LICENSES/",
    "docs/",
    "scripts/build-logos.py",
    "scripts/cleanup-ghcr-images.sh",
    "scripts/logos/",
)

# Paths whose change requires publishing the base image.
IMAGE_SOURCES = (
    "src/images/",
    ".github/workflows/images.yml",
)

# Features whose service depends on the Ansible Feature's `ansible-setup` oneshot.
ANSIBLE_DEPENDENTS = [
    "caddy",
    "codex-cli",
    "dagu",
    "docker-in-docker",
    "docker-outside-of-docker",
    "openbao-agent",
    "opencodex",
    "openobserve",
    "opentelemetry-collector",
    "sshd",
    "t3code-server",
]

# Runtime scripts whose name is not a Feature id: scripts/test-<name>-runtime.sh.
RUNTIME_SCRIPTS = {
    "ansible-dependency": ANSIBLE_DEPENDENTS,
    "codex": ["codex-cli"],
    "codex-caddy": ["codex-cli", "caddy"],
    "codex-exec": ["codex-cli"],
    "openbao-secret-files": ["openbao-agent"],
    "t3code": ["t3code-server"],
}


# Test entry points that do not follow the test-<feature>-runtime.sh convention.
SCRIPT_TARGETS = {
    "scripts/test-sdk-features.sh": ["dart", "flutter"],
}

# Ownership of workflow jobs whose edits can be isolated from the full suite.
# Unknown jobs and workflow-wide changes deliberately select every target.
JOB_TARGETS = {
    "test-sdk-features": ["dart", "flutter"],
}


def targets_for_workflow(before, after):
    """Select owners of changed jobs, retaining a full-suite fallback."""
    try:
        import yaml

        old = yaml.safe_load(before)
        new = yaml.safe_load(after)
        if not isinstance(old, dict) or not isinstance(new, dict):
            return None
        if {k: v for k, v in old.items() if k != "jobs"} != {k: v for k, v in new.items() if k != "jobs"}:
            return None
        old_jobs, new_jobs = old.get("jobs"), new.get("jobs")
        if not isinstance(old_jobs, dict) or not isinstance(new_jobs, dict):
            return None
        selected = set()
        for job in old_jobs.keys() | new_jobs.keys():
            if old_jobs.get(job) != new_jobs.get(job):
                if job not in JOB_TARGETS:
                    return None
                selected.update(JOB_TARGETS[job])
        return sorted(selected)
    except (ImportError, ValueError, TypeError) as error:
        print(f"Unable to compare CI workflow; selecting every target: {error}", file=sys.stderr)
        return None
    except yaml.YAMLError as error:
        print(f"Unable to parse CI workflow; selecting every target: {error}", file=sys.stderr)
        return None


def workflow_targets_at(base, head):
    contents = []
    for revision in (base, head):
        result = subprocess.run(
            ["git", "show", f"{revision}:.github/workflows/ci.yml"],
            cwd=ROOT, text=True, capture_output=True,
        )
        if result.returncode != 0:
            return None
        contents.append(result.stdout)
    return targets_for_workflow(*contents)


def all_features():
    return sorted(path.name for path in FEATURES_DIR.iterdir() if (path / "devcontainer-feature.json").is_file())


def all_targets():
    return all_features() + ["base-image", "template"]


def targets_for(path, features, workflow_targets=None):
    """Return the targets a changed path selects, or None for every target."""
    if path == ".github/workflows/ci.yml":
        return workflow_targets
    if path in SCRIPT_TARGETS:
        return SCRIPT_TARGETS[path]
    if path.startswith(SHARED):
        return None
    for prefix in ("src/features/", "test/features/"):
        if path.startswith(prefix):
            name = path[len(prefix):].split("/", 1)[0]
            return [name] if name in features else None
    if path.startswith("src/templates/"):
        return ["template"]
    if path.startswith("test/ansible-dependency/"):
        return ANSIBLE_DEPENDENTS
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


def select(paths, workflow_targets=None):
    if paths is None:
        return all_targets()
    features = set(all_features())
    selected = set()
    for path in paths:
        targets = targets_for(path, features, workflow_targets)
        if targets is None:
            print(f"{path} affects every target.", file=sys.stderr)
            return all_targets()
        selected.update(targets)
    return sorted(add_dependents(selected, features))


def images_changed(paths):
    return paths is None or any(path.startswith(IMAGE_SOURCES) for path in paths)


def main(argv):
    if argv == ["--all"]:
        paths = None
    elif len(argv) == 2:
        paths = changed_paths(argv[0], argv[1])
    else:
        print(__doc__, file=sys.stderr)
        return 2
    workflow_targets = workflow_targets_at(*argv) if paths is not None and ".github/workflows/ci.yml" in paths else None
    targets = select(paths, workflow_targets)
    images = images_changed(paths)
    print(f"Selected targets: {', '.join(targets) or '(none)'}", file=sys.stderr)
    print(f"Publish base image: {str(images).lower()}", file=sys.stderr)
    print("targets=" + json.dumps(targets, separators=(",", ":")))
    print("images=" + str(images).lower())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
