#!/usr/bin/env python3
"""Resolve a T3 Code package source and version to something the installer can fetch.

Usage: resolve-package-source.py PACKAGE_SOURCE VERSION ARCH

ARCH is the Node.js architecture name of the target machine: `x64` or `arm64`.

Prints four lines:

1. kind: `archive` (a self-contained release archive) or `npm` (an npm install)
2. source: the archive URL, or the npm package spec / tarball URL
3. version: the exact resolved version, or empty when npm decides it
4. checksums: the SHA256SUMS URL beside the archive, or empty

An empty package source is upstream T3 Code. An exact version, or `latest`,
installs the release archive from upstream's GitHub Releases. Any other
version string is an npm range or dist-tag and installs `t3@<version>`
through npm.

A `github:<owner>/<repository>` source is a fork that publishes
`server/<version>` releases. `latest` selects the greatest stable
`server/*-wyrd.*` tag by SemVer precedence. The release archive is
preferred; when the release carries only the npm tarball, that tarball is
installed through npm.

Any other non-empty source is passed to npm unchanged.
"""

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


UPSTREAM_REPOSITORY = "pingdotgg/t3code"
USER_AGENT = "t3code-server-feature"
ARCHITECTURES = ("x64", "arm64")

GITHUB_SOURCE = re.compile(
    r"^github:([A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?)/"
    r"([A-Za-z0-9](?:[A-Za-z0-9_.-]{0,98}[A-Za-z0-9_])?)$"
)
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-((?:0|[1-9A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
FORK_VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-wyrd\.(0|[1-9][0-9]*)$")
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


def fork_version_key(version):
    match = FORK_VERSION.fullmatch(version)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def select_latest(refs):
    candidates = []
    for ref in refs:
        prefix = "refs/tags/server/"
        if not ref.startswith(prefix):
            continue
        version = ref[len(prefix) :]
        key = fork_version_key(version)
        if key is not None:
            candidates.append((key, version))
    if not candidates:
        raise ValueError("No stable fork releases exist in the server/*-wyrd.* tag namespace.")
    return max(candidates)[1]


def fetch_refs(owner, repository, api_base="https://api.github.com"):
    path = f"/repos/{owner}/{repository}/git/matching-refs/tags/server/"
    request = urllib.request.Request(
        f"{api_base.rstrip('/')}{path}",
        headers={"Accept": "application/vnd.github+json", "User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    if not isinstance(payload, list):
        raise ValueError("GitHub returned an invalid tag response.")
    return [item.get("ref", "") for item in payload if isinstance(item, dict)]


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


def asset_exists(url):
    """Whether a release asset exists, by one anonymous HEAD request."""
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30):
            return True
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return False
        raise


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


def resolve_fork(
    owner,
    repository,
    version,
    arch,
    api_base="https://api.github.com",
    web_base="https://github.com",
    exists=None,
):
    resolved_version = select_latest(fetch_refs(owner, repository, api_base)) if version.lower() == "latest" else version
    if not SEMVER.fullmatch(resolved_version):
        raise ValueError(f"GitHub package version is not valid SemVer: {resolved_version!r}.")

    download_base = f"{web_base.rstrip('/')}/{owner}/{repository}/releases/download"
    tag = urllib.parse.quote(f"server/{resolved_version}", safe="/")
    archive_url = f"{download_base}/{tag}/{urllib.parse.quote(archive_name(resolved_version, arch), safe='')}"
    if (exists or asset_exists)(archive_url):
        return Resolution("archive", archive_url, resolved_version, f"{download_base}/{tag}/SHA256SUMS")

    tarball = urllib.parse.quote(f"t3-{resolved_version}.tgz", safe="")
    return Resolution("npm", f"{download_base}/{tag}/{tarball}", resolved_version)


def resolve(
    package_source,
    version,
    arch,
    api_base="https://api.github.com",
    web_base="https://github.com",
    exists=None,
    latest=None,
):
    if arch not in ARCHITECTURES:
        raise ValueError(f"Unsupported architecture {arch!r}; expected one of {', '.join(ARCHITECTURES)}.")

    match = GITHUB_SOURCE.fullmatch(package_source)
    if match:
        owner, repository = match.groups()
        return resolve_fork(owner, repository, version, arch, api_base, web_base, exists)
    if package_source.startswith("github:"):
        raise ValueError("GitHub package source must have the form github:<owner>/<repository>.")
    if package_source:
        return Resolution("npm", package_source)
    return resolve_upstream(version, arch, web_base, latest)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: resolve-package-source.py PACKAGE_SOURCE VERSION ARCH")
    try:
        resolution = resolve(sys.argv[1], sys.argv[2], sys.argv[3])
    except (ValueError, OSError) as error:
        raise SystemExit(f"ERROR: {error}") from error
    print("\n".join(resolution.lines()))


if __name__ == "__main__":
    main()
