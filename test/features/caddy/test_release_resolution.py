#!/usr/bin/env python3
"""Exercise feature release resolution with controlled HTTP responses."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
REPOS = {"caddy": "caddyserver/caddy"}


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

    def test_stable_latest_redirect_avoids_api(self):
        host, _ = self.urls("caddy")
        for architecture in ("amd64", "arm64"):
            with self.subTest(architecture=architecture):
                result, calls = self.resolve("caddy", {host + "/latest": {"body": host + "/tag/v2.3.4"}}, architecture)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "2.3.4\n")
                self.assertEqual(calls, [host + "/latest"])

    def test_invalid_redirect_or_transport_failure_falls_back_to_api(self):
        host, api = self.urls("caddy")
        for redirect in ({"status": 22}, {"body": host + "/tag/v2.3.4-rc1"},
                         {"body": "https://example.test/releases/tag/v2.3.4"},
                         {"body": host + "/latest"}):
            with self.subTest(redirect=redirect):
                responses = {host + "/latest": redirect, api + "/latest": {"body": json.dumps({"tag_name": "v2.3.3"})}}
                result, calls = self.resolve("caddy", responses)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "2.3.3\n")
                self.assertEqual(calls, [host + "/latest", api + "/latest"])

    def test_failed_fallback_is_reported(self):
        host, api = self.urls("caddy")
        responses = {host + "/latest": {"status": 22}, api + "/latest": {"status": 22}}
        result, calls = self.resolve("caddy", responses)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unable to query Caddy releases", result.stderr)
        self.assertEqual(calls, [host + "/latest", api + "/latest"])


if __name__ == "__main__":
    unittest.main()
