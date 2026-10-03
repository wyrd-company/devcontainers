#!/usr/bin/env python3
"""Resolve a T3 Code version to something the installer can fetch.

Usage: resolve-package-source.py VERSION ARCH

ARCH is the Node.js architecture name of the target machine: `x64` or `arm64`.

Prints four lines:

1. kind: `archive` (a self-contained release archive) or `npm` (an npm install)
2. source: the archive URL, or the npm package spec
3. version: the exact resolved version, or empty when npm decides it
4. checksums: the SHA256SUMS URL beside the archive, or empty

An exact version, or `latest`, installs the release archive from upstream's
GitHub Releases. Any other version string is an npm range or dist-tag and
installs `t3@<version>` through npm.
"""

import re
import sys
import urllib.parse
import urllib.request


UPSTREAM_REPOSITORY = "pingdotgg/t3code"
USER_AGENT = "t3code-server-feature"
ARCHITECTURES = ("x64", "arm64")

SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
UPSTREAM_RELEASE_TAG = re.compile(r"/releases/tag/v([^/]+)$")


class Resolution:
    def __init__(self, kind, source, version="", checksums=""):
        self.kind = kind
        self.source = source
        self.version = version
        self.checksums = checksums

    def lines(self):
        return [self.kind, self.source, self.version, self.checksums]


def archive_name(version, arch):
    return f"t3-{version}-linux-{arch}.tar.gz"


def fetch_upstream_latest(web_base="https://github.com"):
    """The version GitHub marks as the latest upstream release.

    The `releases/latest` page redirects to the release tag, so one anonymous
    request answers without touching the rate-limited API.
    """
    request = urllib.request.Request(
        f"{web_base.rstrip('/')}/{UPSTREAM_REPOSITORY}/releases/latest",
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        final_url = response.geturl()
    match = UPSTREAM_RELEASE_TAG.search(urllib.parse.urlparse(final_url).path)
    if not match:
        raise ValueError("GitHub did not redirect to an upstream release tag.")
    version = urllib.parse.unquote(match.group(1))
    if not SEMVER.fullmatch(version):
        raise ValueError(f"Upstream latest release tag is not valid SemVer: {version!r}.")
    return version


def upstream_release_download_base(web_base="https://github.com"):
    return f"{web_base.rstrip('/')}/{UPSTREAM_REPOSITORY}/releases/download"


def resolve_upstream(version, arch, web_base="https://github.com", latest=None):
    if version.lower() == "latest":
        resolved_version = (latest or fetch_upstream_latest)(web_base)
    elif SEMVER.fullmatch(version):
        resolved_version = version
    else:
        return Resolution("npm", f"t3@{version}")

    tag = urllib.parse.quote(f"v{resolved_version}", safe="")
    base = f"{upstream_release_download_base(web_base)}/{tag}"
    return Resolution(
        "archive",
        f"{base}/{urllib.parse.quote(archive_name(resolved_version, arch), safe='')}",
        resolved_version,
        f"{base}/SHA256SUMS",
    )


def resolve(version, arch, web_base="https://github.com", latest=None):
    if arch not in ARCHITECTURES:
        raise ValueError(f"Unsupported architecture {arch!r}; expected one of {', '.join(ARCHITECTURES)}.")
    return resolve_upstream(version, arch, web_base, latest)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: resolve-package-source.py VERSION ARCH")
    try:
        resolution = resolve(sys.argv[1], sys.argv[2])
    except (ValueError, OSError) as error:
        raise SystemExit(f"ERROR: {error}") from error
    print("\n".join(resolution.lines()))


if __name__ == "__main__":
    main()
