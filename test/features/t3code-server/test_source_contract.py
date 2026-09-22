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
    def test_metadata_documents_sources_and_in_place_update(self):
        metadata = json.loads((FEATURE / "devcontainer-feature.json").read_text())
        self.assertEqual(metadata["version"], "2.0.0")
        self.assertIn("github:wyrd-company/t3code", metadata["options"]["packageSource"]["description"])
        self.assertIn("SemVer precedence", metadata["options"]["version"]["description"])
        self.assertIn("t3code-server-update", metadata["description"])
        self.assertNotIn("releaseBaseUrl", metadata["options"])

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

    def test_upstream_scenario_and_assertion_agree_on_explicit_version(self):
        scenarios = json.loads((TEST / "scenarios.json").read_text())
        options = scenarios["t3code-server-upstream-archive"]["features"]["t3code-server"]
        assertion = (TEST / "t3code-server-upstream-archive.sh").read_text()
        self.assertNotIn("packageSource", options)
        version_assertion = re.search(
            r'^check "upstream T3 reports the pinned version" test "\$\(/usr/local/bin/t3 --version\)" = "t3 v([^" ]+)"$',
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
            r'^resolved_version="\$\{resolution\[([0-9]+)\]\}"$',
            installer,
            re.MULTILINE,
        )
        verification = re.findall(
            r'^"\$\(dirname "\$0"\)/([^" ]+)" "\$\{installed_version\}" "\$\{resolved_version\}"$',
            installer,
            re.MULTILINE,
        )
        self.assertEqual(resolved_assignment, ["2"])
        self.assertEqual(verification, ["verify-version.sh"])
        self.assertTrue((FEATURE / verification[0]).is_file())

    def test_installer_runs_the_selected_version_and_grants_only_the_update_command(self):
        installer = (FEATURE / "install.sh").read_text()
        self.assertIn('t3code-runtime selected-entry)" "\\${args[@]}"', installer)
        self.assertIn('--base-dir "\\${HOME}/.t3"', installer)
        self.assertIn("/usr/local/bin/t3code-server-update", installer)
        grant = re.search(
            r'^\$\{service_user\} ALL=\(root\) NOPASSWD: (.*)$', installer, re.MULTILINE
        )
        self.assertIsNotNone(grant)
        self.assertEqual(
            grant.group(1),
            "/usr/local/bin/t3code-server-update, /usr/local/bin/t3code-server-update *",
        )
        self.assertIn("visudo --check --file=/etc/sudoers.d/t3code-server", installer)
        self.assertIn('if [ "${service_user}" != root ]', installer)
        for tool in ("t3code-runtime", "t3code-server-update", "resolve-package-source.py"):
            with self.subTest(tool=tool):
                self.assertTrue((FEATURE / tool).is_file())

    def test_update_command_uses_the_installed_resolver_and_runtime_tool(self):
        update = (FEATURE / "t3code-server-update").read_text()
        self.assertIn('"${lib_dir}/resolve-package-source.py"', update)
        self.assertIn('"${runtime}" install-archive', update)
        self.assertIn('"${runtime}" select', update)
        self.assertIn("/command/s6-svc -r", update)

    def test_readme_documents_explicit_and_latest_github_examples(self):
        readme = (FEATURE / "README.md").read_text()
        self.assertGreaterEqual(readme.count('"packageSource": "github:wyrd-company/t3code"'), 2)
        self.assertIn('"version": "0.0.42-wyrd.2"', readme)
        self.assertIn('"version": "latest"', readme)
        self.assertIn("sudo t3code-server-update", readme)
        self.assertIn("/etc/sudoers.d/t3code-server", readme)

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
            r"(?ms)^  test-t3code-runtime:\n    runs-on: ubuntu-latest\n    timeout-minutes: 15$",
        )


if __name__ == "__main__":
    unittest.main()
