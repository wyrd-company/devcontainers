#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import unittest
import urllib.error
from unittest import mock


SCRIPT = pathlib.Path(__file__).parents[3] / "src/features/t3code-server/resolve-package-source.py"
SPEC = importlib.util.spec_from_file_location("resolve_package_source", SCRIPT)
resolver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolver)

FORK = "github:sample-owner/sample-repository"
FORK_DOWNLOADS = "https://github.com/sample-owner/sample-repository/releases/download"
UPSTREAM_DOWNLOADS = "https://github.com/pingdotgg/t3code/releases/download"


class Response:
    def __init__(self, payload=None, url=""):
        self.payload = payload
        self.url = url

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps(self.payload).encode()

    def geturl(self):
        return self.url


def present(_url):
    return True


def absent(_url):
    return False


def lines(resolution):
    return resolution.lines()


class UpstreamSourceTests(unittest.TestCase):
    def test_exact_upstream_version_installs_the_release_archive(self):
        self.assertEqual(
            lines(resolver.resolve("", "1.2.3", "x64")),
            [
                "archive",
                f"{UPSTREAM_DOWNLOADS}/v1.2.3/t3-1.2.3-linux-x64.tar.gz",
                "1.2.3",
                f"{UPSTREAM_DOWNLOADS}/v1.2.3/SHA256SUMS",
                "",
            ],
        )

    def test_archive_name_follows_the_target_architecture(self):
        resolution = resolver.resolve("", "1.2.3", "arm64")
        self.assertTrue(resolution.source.endswith("/t3-1.2.3-linux-arm64.tar.gz"))

    def test_upstream_latest_follows_the_latest_release_redirect(self):
        with mock.patch.object(resolver, "fetch_upstream_latest", return_value="4.5.6") as latest:
            resolution = resolver.resolve("", "latest", "x64")
        latest.assert_called_once()
        self.assertEqual(resolution.kind, "archive")
        self.assertEqual(resolution.version, "4.5.6")
        self.assertEqual(resolution.source, f"{UPSTREAM_DOWNLOADS}/v4.5.6/t3-4.5.6-linux-x64.tar.gz")

    def test_latest_release_redirect_is_one_anonymous_request(self):
        response = Response(url="https://github.com/pingdotgg/t3code/releases/tag/v4.5.6")
        with mock.patch.object(resolver.urllib.request, "urlopen", return_value=response) as opened:
            self.assertEqual(resolver.fetch_upstream_latest(), "4.5.6")
        opened.assert_called_once()
        request = opened.call_args.args[0]
        self.assertEqual(request.full_url, "https://github.com/pingdotgg/t3code/releases/latest")
        self.assertNotIn("Authorization", request.headers)
        self.assertEqual(opened.call_args.kwargs["timeout"], 30)

    def test_latest_release_redirect_must_name_a_semver_tag(self):
        for url in (
            "https://github.com/pingdotgg/t3code/releases",
            "https://github.com/pingdotgg/t3code/releases/tag/v1.2",
        ):
            with self.subTest(url=url):
                with mock.patch.object(resolver.urllib.request, "urlopen", return_value=Response(url=url)):
                    with self.assertRaises(ValueError):
                        resolver.fetch_upstream_latest()

    def test_npm_ranges_and_dist_tags_install_through_npm(self):
        for version in ("^1.2.3", "1.2", "next"):
            with self.subTest(version=version):
                self.assertEqual(lines(resolver.resolve("", version, "x64")), ["npm", f"t3@{version}", "", "", ""])

    def test_explicit_npm_spec_and_url_are_passed_to_npm_unchanged(self):
        for source in ("example-package@1.2.3", "https://packages.example.test/tool.tgz"):
            with self.subTest(source=source):
                self.assertEqual(lines(resolver.resolve(source, "latest", "x64")), ["npm", source, "", "", ""])

    def test_unsupported_architecture_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unsupported architecture"):
            resolver.resolve("", "1.2.3", "ppc64")


class ForkSourceTests(unittest.TestCase):
    def test_explicit_fork_version_derives_release_archive_without_discovery(self):
        with mock.patch.object(resolver, "fetch_refs") as fetch:
            resolution = resolver.resolve(FORK, "1.2.3-wyrd.4", "x64", exists=present)
        fetch.assert_not_called()
        self.assertEqual(
            lines(resolution),
            [
                "archive",
                f"{FORK_DOWNLOADS}/server/1.2.3-wyrd.4/t3-1.2.3-wyrd.4-linux-x64.tar.gz",
                "1.2.3-wyrd.4",
                f"{FORK_DOWNLOADS}/server/1.2.3-wyrd.4/SHA256SUMS",
                f"{FORK_DOWNLOADS}/server",
            ],
        )

    def test_fork_release_without_an_archive_installs_its_npm_tarball(self):
        resolution = resolver.resolve(FORK, "1.2.3-wyrd.4", "x64", exists=absent)
        self.assertEqual(
            lines(resolution),
            [
                "npm",
                f"{FORK_DOWNLOADS}/server/1.2.3-wyrd.4/t3-1.2.3-wyrd.4.tgz",
                "1.2.3-wyrd.4",
                "",
                f"{FORK_DOWNLOADS}/server",
            ],
        )

    def test_archive_presence_is_probed_with_one_anonymous_head_request(self):
        probed = []

        def exists(url):
            probed.append(url)
            return True

        resolver.resolve(FORK, "1.2.3-wyrd.4", "x64", exists=exists)
        self.assertEqual(probed, [f"{FORK_DOWNLOADS}/server/1.2.3-wyrd.4/t3-1.2.3-wyrd.4-linux-x64.tar.gz"])

    def test_asset_probe_treats_not_found_as_absent_and_raises_otherwise(self):
        not_found = urllib.error.HTTPError("url", 404, "Not Found", {}, None)
        with mock.patch.object(resolver.urllib.request, "urlopen", side_effect=not_found) as opened:
            self.assertFalse(resolver.asset_exists("https://example.test/asset"))
        self.assertEqual(opened.call_args.args[0].get_method(), "HEAD")
        forbidden = urllib.error.HTTPError("url", 403, "Forbidden", {}, None)
        with mock.patch.object(resolver.urllib.request, "urlopen", side_effect=forbidden):
            with self.assertRaises(urllib.error.HTTPError):
                resolver.asset_exists("https://example.test/asset")

    def test_latest_uses_semver_precedence_not_lexical_order(self):
        refs = [
            "refs/tags/server/1.9.0-wyrd.20",
            "refs/tags/server/1.10.0-wyrd.2",
            "refs/tags/server/1.10.0-wyrd.11",
        ]
        with mock.patch.object(resolver, "fetch_refs", return_value=refs):
            resolution = resolver.resolve(FORK, "latest", "x64", exists=present)
        self.assertEqual(resolution.version, "1.10.0-wyrd.11")
        self.assertTrue(resolution.source.endswith("/server/1.10.0-wyrd.11/t3-1.10.0-wyrd.11-linux-x64.tar.gz"))

    def test_latest_rejects_unrelated_malformed_and_other_prerelease_tags(self):
        refs = [
            "refs/tags/v99.0.0",
            "refs/tags/web/99.0.0-wyrd.1",
            "refs/tags/server/99.0.0-alpha.1",
            "refs/tags/server/99.0.0-wyrd.01",
            "refs/tags/server/v99.0.0",
            "refs/tags/server/2.0.0-wyrd.3",
        ]
        self.assertEqual(resolver.select_latest(refs), "2.0.0-wyrd.3")

    def test_latest_fails_when_no_stable_fork_tag_exists(self):
        with self.assertRaisesRegex(ValueError, "No stable fork releases"):
            resolver.select_latest(["refs/tags/server/3.0.0-alpha.1"])

    def test_github_repository_identity_is_validated(self):
        invalid_sources = (
            "github:../sample-repository",
            "github:-sample-owner/sample-repository",
            "github:.sample-owner/sample-repository",
            "github:sample-owner/sample-repository/../../unexpected",
            "github:sample-owner/.",
            "github:sample-owner/..",
            "github:sample-owner/-sample-repository",
            "github:sample-owner/.sample-repository",
        )
        for source in invalid_sources:
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "github:<owner>/<repository>"):
                resolver.resolve(source, "1.2.3", "x64")

    def test_explicit_github_version_must_be_semver(self):
        for version in ("../../../unexpected/path", "1.2", "next"):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, "not valid SemVer"):
                resolver.resolve(FORK, version, "x64", exists=present)

    def test_tag_discovery_uses_one_anonymous_matching_refs_request(self):
        payload = [{"ref": f"refs/tags/server/1.0.0-wyrd.{number}"} for number in range(1, 102)]
        with mock.patch.object(resolver.urllib.request, "urlopen", return_value=Response(payload)) as opened:
            refs = resolver.fetch_refs("sample-owner", "sample-repository")
        self.assertEqual(len(refs), 101)
        opened.assert_called_once()
        request = opened.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "https://api.github.com/repos/sample-owner/sample-repository/git/matching-refs/tags/server/",
        )
        self.assertEqual(resolver.urllib.parse.urlsplit(request.full_url).query, "")
        self.assertNotIn("Authorization", request.headers)
        self.assertEqual(opened.call_args.kwargs["timeout"], 30)

    def test_tag_discovery_rejects_non_list_response(self):
        with mock.patch.object(resolver.urllib.request, "urlopen", return_value=Response({"tag_name": "unrelated"})):
            with self.assertRaisesRegex(ValueError, "invalid tag response"):
                resolver.fetch_refs("sample-owner", "sample-repository")


if __name__ == "__main__":
    unittest.main()
