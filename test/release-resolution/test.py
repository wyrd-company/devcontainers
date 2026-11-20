#!/usr/bin/env python3
"""Exercise feature release resolution with controlled HTTP responses."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
REPOS = {"caddy": "caddyserver/caddy", "openbao-agent": "openbao/openbao", "openobserve": "openobserve/openobserve"}


class ReleaseTests(unittest.TestCase):
    def resolve(self, feature, responses, architecture="amd64"):
        script = (ROOT / "src/features" / feature / "install.sh").read_text().split('[ "$(id -u)" -eq 0 ]')[0]
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            (temp / "responses").write_text(json.dumps(responses))
            curl = temp / "curl"
            curl.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['FIXTURE'])
url = sys.argv[-1]
with (p / 'calls').open('a') as f: f.write(url + '\\n')
response = json.loads((p / 'responses').read_text()).get(url)
if response is None:
    print('Unexpected request: ' + url, file=sys.stderr)
    sys.exit(90)
print(response.get('body', ''), end='')
sys.exit(response.get('status', 0))
''')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f"{temp}:{os.environ['PATH']}", FIXTURE=str(temp))
            env.pop("GITHUB_TOKEN", None)
            result = subprocess.run(["bash", "-c", script + f'\narchitecture="{architecture}"\nresolve_latest_version\n'], env=env, capture_output=True, text=True)
            calls = (temp / "calls").read_text().splitlines() if (temp / "calls").exists() else []
            return result, calls

    def urls(self, feature):
        repo = REPOS[feature]
        host = f"https://github.com/{repo}/releases"
        return host, f"https://api.github.com/repos/{repo}/releases"

    def test_latest_redirect_avoids_api(self):
        for feature in REPOS:
            for arch in ("amd64", "arm64"):
                with self.subTest(feature=feature, arch=arch):
                    host, _ = self.urls(feature)
                    responses = {host + "/latest": {"body": host + "/tag/v1.2.3"}}
                    if feature == "openbao-agent":
                        responses[host + f"/download/v1.2.3/openbao_1.2.3_linux_{arch}.tar.gz"] = {"body": "200"}
                    result, calls = self.resolve(feature, responses, arch)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, ("v" if feature == "openobserve" else "") + "1.2.3\n")
                    self.assertTrue(all(not url.startswith("https://api.github.com/") for url in calls))
                    self.assertEqual(len(calls), 2 if feature == "openbao-agent" else 1)

    def test_redirect_failure_falls_back_to_api(self):
        for feature in REPOS:
            with self.subTest(feature=feature):
                host, api = self.urls(feature)
                release = {"tag_name": "v1.2.2", "draft": False, "prerelease": False,
                           "assets": [{"name": "openbao_1.2.2_linux_amd64.tar.gz"}]}
                api_url = api + ("/latest" if feature == "caddy" else "?per_page=20&page=1" if feature == "openbao-agent" else "")
                responses = {host + "/latest": {"status": 22}, api_url: {"body": json.dumps(release if feature == "caddy" else [release])}}
                result, calls = self.resolve(feature, responses)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, ("v" if feature == "openobserve" else "") + "1.2.2\n")
                self.assertEqual(calls, [host + "/latest", api_url])

    def test_openobserve_prerelease_redirect_falls_back_to_stable_api_release(self):
        host, api = self.urls("openobserve")
        releases = [{"tag_name": "v1.2.0-rc2", "draft": False, "prerelease": True},
                    {"tag_name": "v1.1.9", "draft": False, "prerelease": False}]
        result, calls = self.resolve("openobserve", {host + "/latest": {"body": host + "/tag/v1.2.0-rc2"}, api: {"body": json.dumps(releases)}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "v1.1.9\n")
        self.assertEqual(calls, [host + "/latest", api])

    def test_openbao_missing_latest_archive_searches_older_release(self):
        host, api = self.urls("openbao-agent")
        url = api + "?per_page=20&page=1"
        release = {"tag_name": "v1.2.2", "draft": False, "prerelease": False, "assets": [{"name": "openbao_1.2.2_linux_arm64.tar.gz"}]}
        responses = {host + "/latest": {"body": host + "/tag/v1.2.3"}, host + "/download/v1.2.3/openbao_1.2.3_linux_arm64.tar.gz": {"body": "404"}, url: {"body": json.dumps([release])}}
        result, calls = self.resolve("openbao-agent", responses, "arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "1.2.2\n")
        self.assertEqual(calls[-1], url)

    def test_openbao_archive_server_error_fails_without_api(self):
        host, _ = self.urls("openbao-agent")
        responses = {host + "/latest": {"body": host + "/tag/v1.2.3"}, host + "/download/v1.2.3/openbao_1.2.3_linux_amd64.tar.gz": {"body": "500"}}
        result, calls = self.resolve("openbao-agent", responses)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTTP 500", result.stderr)
        self.assertEqual(len(calls), 2)

    def test_openobserve_retains_known_version_if_both_lookups_fail(self):
        host, api = self.urls("openobserve")
        result, calls = self.resolve("openobserve", {host + "/latest": {"status": 22}, api: {"status": 22}})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "v0.92.2\n")
        self.assertEqual(calls, [host + "/latest", api])


if __name__ == "__main__":
    unittest.main()
