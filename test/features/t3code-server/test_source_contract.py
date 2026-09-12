#!/usr/bin/env python3

import json
import pathlib
import re
import subprocess
import unittest


ROOT = pathlib.Path(__file__).parents[3]
FEATURE = ROOT / "src/features/t3code-server"
TEST = ROOT / "test/features/t3code-server"


class SourceContractTests(unittest.TestCase):
    def test_metadata_documents_github_source_and_semver_latest(self):
        metadata = json.loads((FEATURE / "devcontainer-feature.json").read_text())
        self.assertIn("github:wyrd-company/t3code", metadata["options"]["packageSource"]["description"])
        self.assertIn("SemVer precedence", metadata["options"]["version"]["description"])

    def test_fork_scenario_and_assertion_agree_on_explicit_version(self):
        scenarios = json.loads((TEST / "scenarios.json").read_text())
        options = scenarios["t3code-server-fork-package-source"]["features"]["t3code-server"]
        assertion = (TEST / "t3code-server-fork-package-source.sh").read_text()
        self.assertEqual(options["packageSource"], "github:wyrd-company/t3code")
        version_assertion = re.search(
            r'^check "fork T3 reports the published version" test "\$\(/usr/local/bin/t3 --version\)" = "t3 v([^" ]+)"$',
            assertion,
            re.MULTILINE,
        )
        self.assertIsNotNone(version_assertion)
        self.assertEqual(version_assertion.group(1), options["version"])

    def test_installed_version_mismatch_fails(self):
        result = subprocess.run(
            [FEATURE / "verify-version.sh", "t3 v1.2.3-wyrd.4", "1.2.3-wyrd.5"],
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            result.stderr,
            "ERROR: Installed T3 Code version 't3 v1.2.3-wyrd.4' does not match resolved version '1.2.3-wyrd.5'.\n",
        )

    def test_installed_version_agreement_passes(self):
        subprocess.run(
            [FEATURE / "verify-version.sh", "t3 v1.2.3-wyrd.4", "1.2.3-wyrd.4"],
            check=True,
        )

    def test_installer_wires_resolved_version_into_executable_check(self):
        installer = (FEATURE / "install.sh").read_text()
        resolved_assignment = re.findall(
            r'^resolved_version="\$\{package_resolution\[([0-9]+)\]\}"$',
            installer,
            re.MULTILINE,
        )
        verification = re.findall(
            r'^"\$\(dirname "\$0"\)/([^" ]+)" "\$\{installed_version\}" "\$\{resolved_version\}"$',
            installer,
            re.MULTILINE,
        )
        self.assertEqual(resolved_assignment, ["1"])
        self.assertEqual(verification, ["verify-version.sh"])
        self.assertTrue((FEATURE / verification[0]).is_file())

    def test_readme_documents_explicit_and_latest_github_examples(self):
        readme = (FEATURE / "README.md").read_text()
        self.assertGreaterEqual(readme.count('"packageSource": "github:wyrd-company/t3code"'), 2)
        self.assertIn('"version": "0.0.37-wyrd.1"', readme)
        self.assertIn('"version": "latest"', readme)

    def test_runtime_probe_is_bounded_and_reports_container_state(self):
        runtime_test = (ROOT / "scripts/test-t3code-runtime.sh").read_text()
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()

        self.assertIn("--connect-timeout 2", runtime_test)
        self.assertIn("--max-time 5", runtime_test)
        self.assertIn("deadline=$((SECONDS + 120))", runtime_test)
        self.assertIn('docker inspect --format', runtime_test)
        self.assertIn('docker logs "${name}"', runtime_test)
        self.assertRegex(
            workflow,
            r"(?ms)^  test-t3code-runtime:\n    runs-on: ubuntu-latest\n    timeout-minutes: 10$",
        )


if __name__ == "__main__":
    unittest.main()
