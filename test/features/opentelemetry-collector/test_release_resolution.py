#!/usr/bin/env python3
"""Check release selection with deterministic HTTP responses and real jq parsing."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

FEATURE = Path(__file__).resolve().parents[3] / "src/features/opentelemetry-collector"
HOST = "https://github.com/open-telemetry/opentelemetry-collector-releases/releases"
API = "https://api.github.com/repos/open-telemetry/opentelemetry-collector-releases/releases?per_page=20&page="


def release(version, binary="otelcol", architecture="amd64", **flags):
    return {"tag_name": f"v{version}", "draft": False, "prerelease": False,
            "assets": [{"name": f"{binary}_{version}_linux_{architecture}.tar.gz"}], **flags}


class ReleaseResolutionTests(unittest.TestCase):
    def resolve(self, responses, binary="otelcol", architecture="amd64"):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "responses.json").write_text(json.dumps(responses))
            curl = work / "curl"
            curl.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
work = Path(os.environ["SAMPLE_HTTP_FIXTURE"])
args = sys.argv[1:]
url = args[-1]
with (work / "requests.jsonl").open("a") as output:
    output.write(json.dumps({"url": url, "head": "--head" in args}) + "\\n")
response = json.loads((work / "responses.json").read_text()).get(url)
if response is None:
    print("Unexpected request: " + url, file=sys.stderr)
    sys.exit(90)
print(response.get("output", ""), end="")
sys.exit(response.get("exit", 0))
''')
            curl.chmod(0o755)
            env = os.environ.copy()
            env.pop("GITHUB_TOKEN", None)
            env.update(PATH=f"{work}:{env['PATH']}", SAMPLE_HTTP_FIXTURE=str(work))
            result = subprocess.run(["bash", "-c", '''
set -euo pipefail
source "$1/common.sh"
log() { printf '%s\\n' "$*"; }
err() { printf '%s\\n' "$*" >&2; exit 1; }
upstream_binary="$2"
architecture="$3"
distribution=core
[ "$upstream_binary" != otelcol-contrib ] || distribution=contrib
resolve_latest_version
''', "sample-resolver", str(FEATURE), binary, architecture],
                                    env=env, text=True, capture_output=True, timeout=30)
            calls = [json.loads(line) for line in (work / "requests.jsonl").read_text().splitlines()]
            return result, calls

    def base(self, binary="otelcol", architecture="amd64", status="200"):
        archive = f"{HOST}/download/v1.2.3/{binary}_1.2.3_linux_{architecture}.tar.gz"
        return {f"{HOST}/latest": {"output": f"{HOST}/tag/v1.2.3"}, archive: {"output": status}}

    def test_available_latest_never_uses_api_for_either_distribution_or_architecture(self):
        for binary in ("otelcol", "otelcol-contrib"):
            for architecture in ("amd64", "arm64"):
                with self.subTest(binary=binary, architecture=architecture):
                    result, calls = self.resolve(self.base(binary, architecture), binary, architecture)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "1.2.3\n")
                    self.assertEqual(len(calls), 2)
                    self.assertTrue(calls[-1]["head"])
                    self.assertFalse(any(call["url"].startswith("https://api.github.com/") for call in calls))

    def test_missing_latest_searches_older_pages_and_filters_unstable_or_wrong_assets(self):
        responses = self.base("otelcol-contrib", "arm64", "404")
        responses[API + "1"] = {"output": json.dumps([
            release("1.2.3", "otelcol", "arm64"),
            release("1.2.2", "otelcol-contrib", "amd64"),
            release("1.2.1", "otelcol-contrib", "arm64", prerelease=True),
            release("1.2.0", "otelcol-contrib", "arm64", draft=True),
        ])}
        responses[API + "2"] = {"output": json.dumps([release("1.1.9", "otelcol-contrib", "arm64")])}
        result, calls = self.resolve(responses, "otelcol-contrib", "arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "1.1.9\n")
        self.assertIn("searching older releases", result.stderr)
        self.assertEqual([call["url"] for call in calls[-2:]], [API + "1", API + "2"])

    def test_other_archive_http_errors_do_not_trigger_api(self):
        for status in ("403", "429", "500"):
            with self.subTest(status=status):
                result, calls = self.resolve(self.base(status=status))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"HTTP {status}", result.stderr)
                self.assertEqual(len(calls), 2)

    def test_archive_transport_failure_does_not_trigger_api(self):
        responses = self.base()
        archive = next(url for url in responses if url.endswith(".tar.gz"))
        responses[archive] = {"exit": 7, "output": "000"}
        result, calls = self.resolve(responses)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unable to check", result.stderr)
        self.assertEqual(len(calls), 2)

    def test_invalid_release_redirects_are_rejected_before_asset_or_api_requests(self):
        for tag in (f"{HOST}/tag/v1.2.3-nightly.1", f"{HOST}/tag/cmd/builder/v1.2.3",
                    "https://example.test/releases/tag/v1.2.3", f"{HOST}/latest"):
            with self.subTest(tag=tag):
                result, calls = self.resolve({f"{HOST}/latest": {"output": tag}})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("stable Collector version", result.stderr)
                self.assertEqual(len(calls), 1)

    def test_release_page_failure_stops_without_api(self):
        result, calls = self.resolve({f"{HOST}/latest": {"exit": 22}})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unable to resolve", result.stderr)
        self.assertEqual(len(calls), 1)

    def test_api_failure_is_loud_when_fallback_is_needed(self):
        responses = self.base(status="404")
        responses[API + "1"] = {"exit": 22}
        result, calls = self.resolve(responses)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unable to query", result.stderr)
        self.assertEqual(calls[-1]["url"], API + "1")

    def test_no_matching_stable_release_is_loud(self):
        responses = self.base(status="404")
        responses[API + "1"] = {"output": "[]"}
        result, calls = self.resolve(responses)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No stable OpenTelemetry Collector release contains", result.stderr)
        self.assertEqual(len(calls), 3)


if __name__ == "__main__":
    unittest.main()
