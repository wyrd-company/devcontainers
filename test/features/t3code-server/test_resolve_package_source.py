#!/usr/bin/env python3

import importlib.util
import pathlib
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).parents[3] / "src/features/t3code-server/resolve-package-source.py"
SPEC = importlib.util.spec_from_file_location("resolve_package_source", SCRIPT)
resolver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolver)

UPSTREAM_DOWNLOADS = "https://github.com/pingdotgg/t3code/releases/download"


class Response:
    def __init__(self, url=""):
        self.url = url

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def geturl(self):
        return self.url


def lines(resolution):
    return resolution.lines()


class UpstreamResolutionTests(unittest.TestCase):
    def test_exact_upstream_version_installs_the_release_archive(self):
        self.assertEqual(
            lines(resolver.resolve("1.2.3", "x64")),
            [
                "archive",
                f"{UPSTREAM_DOWNLOADS}/v1.2.3/t3-1.2.3-linux-x64.tar.gz",
                "1.2.3",
                f"{UPSTREAM_DOWNLOADS}/v1.2.3/SHA256SUMS",
            ],
        )

    def test_archive_name_follows_the_target_architecture(self):
        resolution = resolver.resolve("1.2.3", "arm64")
        self.assertTrue(resolution.source.endswith("/t3-1.2.3-linux-arm64.tar.gz"))

    def test_upstream_latest_follows_the_latest_release_redirect(self):
        with mock.patch.object(resolver, "fetch_upstream_latest", return_value="4.5.6") as latest:
            resolution = resolver.resolve("latest", "x64")
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
                self.assertEqual(lines(resolver.resolve(version, "x64")), ["npm", f"t3@{version}", "", ""])

    def test_unsupported_architecture_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unsupported architecture"):
            resolver.resolve("1.2.3", "ppc64")


if __name__ == "__main__":
    unittest.main()
