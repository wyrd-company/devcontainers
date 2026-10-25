#!/usr/bin/env python3
"""Build every artifact logo from a frame and an upstream mark.

Each upstream mark is stored once in scripts/logos/marks/<name>.svg: the
project's official SVG with editor metadata, backdrops and wordmarks removed
and the viewBox trimmed to the drawing. The frame for each artifact kind is
defined here, so every logo of a kind has the same frame.

To give a new artifact a logo, add its mark (if it is new), add one LOGOS
entry, run this script, and record the mark's source and terms in the
artifact's NOTES.md. An artifact without a logo needs a NO_LOGO entry.

Usage: build-logos.py          write every logo
       build-logos.py --check  fail when a logo is missing, stale or invalid
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARKS = ROOT / "scripts" / "logos" / "marks"
ARTIFACT_DIRS = ("src/features", "src/images", "src/templates")

# Mid blue that keeps 3:1 contrast on the site's light (#fafafa) and dark
# (#0b0b0c) pages. The white tile lets dark marks read on a dark page.
LINE = "#2563eb"
TILE = "#ffffff"

# Frames on a 128x128 canvas. "area" is the square (x, y, size) that the mark
# is fitted into, keeping its aspect ratio.
FRAMES = {
    # A lined tile with a "+" badge on its lower-right corner.
    "feature": {
        "under": (
            f'<rect x="4" y="4" width="108" height="108" rx="20" fill="{TILE}" stroke="{LINE}" stroke-width="4"/>'
        ),
        "over": (
            f'<circle cx="109" cy="109" r="16" fill="{LINE}" stroke="{TILE}" stroke-width="4"/>'
            f'<path d="M109 100v18M100 109h18" stroke="{TILE}" stroke-width="5" stroke-linecap="round"/>'
        ),
        "area": (22, 22, 72),
    },
    # A lined tile inside a dashed box: the image is a container.
    "image": {
        "under": (
            f'<rect x="4" y="4" width="120" height="120" rx="24" fill="none" stroke="{LINE}" stroke-width="6" stroke-dasharray="12 8"/>'
            f'<rect x="22" y="22" width="84" height="84" rx="14" fill="{TILE}" stroke="{LINE}" stroke-width="4"/>'
        ),
        "over": "",
        "area": (38, 38, 52),
    },
    # The mark alone.
    "template": {"under": "", "over": "", "area": (8, 8, 112)},
}

# Output path -> (artifact directory, frame, mark, scale). Scale evens out the
# optical size of marks that fill their box (solid squares) or barely do.
LOGOS = {
    "src/features/caddy/logo.svg": ("src/features/caddy", "feature", "caddy", 1.0),
    "src/features/codex-cli/logo.svg": ("src/features/codex-cli", "feature", "openai", 1.0),
    "src/features/cursor-agent-cli/logo.svg": ("src/features/cursor-agent-cli", "feature", "cursor", 0.95),
    "src/features/dagu/logo.svg": ("src/features/dagu", "feature", "dagu", 0.9),
    "src/features/grok-cli/logo.svg": ("src/features/grok-cli", "feature", "grok", 0.95),
    "src/features/openbao-agent/logo.svg": ("src/features/openbao-agent", "feature", "openbao", 1.0),
    "src/features/opencode-cli/logo.svg": ("src/features/opencode-cli", "feature", "opencode", 0.9),
    "src/features/opencodex/logo.svg": ("src/features/opencodex", "feature", "opencodex", 1.0),
    "src/features/openobserve/logo.svg": ("src/features/openobserve", "feature", "openobserve", 1.0),
    "src/features/opentelemetry-collector/logo.svg": ("src/features/opentelemetry-collector", "feature", "opentelemetry", 1.0),
    "src/features/pi-coding-agent-cli/logo.svg": ("src/features/pi-coding-agent-cli", "feature", "pi", 0.85),
    "src/features/t3code-server/logo.svg": ("src/features/t3code-server", "feature", "t3code", 1.0),
}

# Artifact directory -> why it has no logo.
NO_LOGO = {
    "src/features/claude-code-cli": "Anthropic's trademark guidelines require written permission to use the Claude logo.",
    "src/features/docker-in-docker": "Docker's trademark guidelines allow word marks, not logo marks, without authorization.",
    "src/features/docker-outside-of-docker": "Docker's trademark guidelines allow word marks, not logo marks, without authorization.",
    "src/features/go": "The Go brand guidelines require permission to use the Go logo.",
    "src/features/sshd": "OpenSSH publishes no SVG logo.",
    "src/images/base-ubuntu": "Canonical requires written permission to use the Ubuntu logo.",
    "src/templates/ubuntu": "The Development Containers project publishes no SVG logo.",
}

FORBIDDEN = re.compile(r"<(script|image|foreignObject|style)\b|\son\w+\s*=|(?:xlink:)?href\s*=\s*\"(?!#)", re.I)


def read_mark(name: str) -> tuple[list[float], str]:
    text = (MARKS / f"{name}.svg").read_text()
    match = re.fullmatch(r'\s*<svg xmlns="http://www.w3.org/2000/svg" viewBox="([^"]+)">(.*)</svg>\s*', text, re.S)
    if match is None:
        raise ValueError(f"{name}: a mark is one <svg> with only xmlns and viewBox attributes")
    return [float(v) for v in match.group(1).split()], match.group(2).strip()


def number(value: float) -> str:
    return f"{value:.2f}".rstrip("0").rstrip(".")


def compose(frame: str, view_box: list[float], body: str, scale: float = 1.0) -> str:
    spec = FRAMES[frame]
    x, y, size = spec["area"]
    _, _, width, height = view_box
    fit = size * scale / max(width, height)
    w, h = width * fit, height * fit
    mark = (
        f'<svg x="{number(x + (size - w) / 2)}" y="{number(y + (size - h) / 2)}" '
        f'width="{number(w)}" height="{number(h)}" viewBox="{" ".join(number(v) for v in view_box)}" '
        f'overflow="visible">{body}</svg>'
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'
        "<!-- Generated by scripts/build-logos.py. Do not edit. -->"
        f'{spec["under"]}{mark}{spec["over"]}</svg>\n'
    )


def problems(svg: str) -> list[str]:
    found = []
    if not svg.startswith('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'):
        found.append("is not a square 128x128 SVG")
    if FORBIDDEN.search(svg):
        found.append("has a script, style, raster image, event handler or external reference")
    return found


def artifact_dirs() -> list[str]:
    return sorted(
        str(path.relative_to(ROOT)) for base in ARTIFACT_DIRS for path in (ROOT / base).iterdir() if path.is_dir()
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail when a committed logo differs from the build")
    check = parser.parse_args().check
    errors = []

    covered = {artifact for artifact, *_ in LOGOS.values()}
    for directory in artifact_dirs():
        if directory not in covered and directory not in NO_LOGO:
            errors.append(f"{directory}: has no LOGOS entry and no NO_LOGO reason")
        if directory in NO_LOGO and (ROOT / directory / "logo.svg").exists():
            errors.append(f"{directory}/logo.svg: exists, but the directory is in NO_LOGO")
    for directory in NO_LOGO:
        if directory in covered:
            errors.append(f"{directory}: is in both LOGOS and NO_LOGO")

    for output, (_, frame, mark, scale) in LOGOS.items():
        svg = compose(frame, *read_mark(mark), scale)
        errors.extend(f"{output}: {problem}" for problem in problems(svg))
        path = ROOT / output
        if check:
            if not path.exists():
                errors.append(f"{output}: is missing; run scripts/build-logos.py")
            elif path.read_text() != svg:
                errors.append(f"{output}: differs from the build; run scripts/build-logos.py")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(svg)

    for error in errors:
        print(error, file=sys.stderr)
    if not errors and not check:
        print(f"wrote {len(LOGOS)} logos")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
