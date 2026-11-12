"""Behavior boundaries for artifact and workflow test selection."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ci_changes", ROOT / "scripts/ci-changes.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)

WORKFLOW = """name: sample-ci
on: [push]
jobs:
  test-sdk-features:
    runs-on: ubuntu-latest
    steps:
      - run: sample-check
"""


class SelectionTests(unittest.TestCase):
    def test_dart_selects_flutter_dependent(self):
        self.assertEqual(ci.select(["src/features/dart/install.sh"]), ["dart", "flutter"])

    def test_flutter_does_not_select_dart(self):
        self.assertEqual(ci.select(["src/features/flutter/install.sh"]), ["flutter"])

    def test_sdk_script_selects_only_sdk_features(self):
        self.assertEqual(ci.select(["scripts/test-sdk-features.sh"]), ["dart", "flutter"])

    def test_vector_runtime_selects_vector(self):
        self.assertEqual(ci.select(["scripts/test-vector-runtime.sh"]), ["vector"])
        self.assertEqual(ci.select(["src/features/vector/install.sh"]), ["vector"])

    def test_every_feature_with_an_ansible_setup_edge_is_an_ansible_dependent(self):
        installers = sorted((ROOT / "src/features").glob("*/install.sh"))
        with_edge = sorted(path.parent.name for path in installers
                           if "dependencies.d/ansible-setup" in path.read_text())
        self.assertEqual(sorted(ci.ANSIBLE_DEPENDENTS), with_edge)

    def test_template_and_documentation(self):
        self.assertEqual(ci.select(["src/templates/ubuntu/NOTES.md"]), ["template"])
        self.assertEqual(ci.select(["docs/user/overview.md"]), [])

    def test_shared_unknown_and_manual_select_everything(self):
        for path in ["scripts/ci-changes.py", "scripts/ci-requirements.txt", "test/ci-changes/test_selection.py",
                     "scripts/test-features.sh", "scripts/check-sudo-no-all.sh", "src/images/base-ubuntu/Dockerfile",
                     "scripts/sample-unknown.sh"]:
            with self.subTest(path=path):
                self.assertEqual(ci.select([path]), ci.all_targets())
        self.assertEqual(ci.select(None), ci.all_targets())

    def test_sdk_job_edits_additions_and_removals(self):
        empty = "name: sample-ci\non: [push]\njobs: {}\n"
        for before, after in [(WORKFLOW, WORKFLOW.replace("sample-check", "sample-check-updated")),
                              (empty, WORKFLOW), (WORKFLOW, empty)]:
            with self.subTest(before=before, after=after):
                targets = ci.targets_for_workflow(before, after)
                self.assertEqual(targets, ["dart", "flutter"])
                self.assertEqual(ci.select([".github/workflows/ci.yml"], targets), ["dart", "flutter"])

    def test_formatting_only_workflow_edit_selects_nothing(self):
        formatted = "# sample comment\n" + yaml.safe_dump(yaml.safe_load(WORKFLOW), sort_keys=True)
        self.assertEqual(ci.targets_for_workflow(WORKFLOW, formatted), [])

    def test_workflow_wide_unknown_and_selector_job_changes_select_everything(self):
        cases = [WORKFLOW.replace("[push]", "[pull_request]"),
                 WORKFLOW + "permissions: read-all\n",
                 WORKFLOW.replace("test-sdk-features:", "sample-unknown-job:"),
                 WORKFLOW + "  changes:\n    runs-on: ubuntu-latest\n",
                 "malformed: [", "[]", "jobs: []"]
        for after in cases:
            with self.subTest(after=after):
                result = ci.targets_for_workflow(WORKFLOW, after)
                self.assertIsNone(result)
                self.assertEqual(ci.select([".github/workflows/ci.yml"], result), ci.all_targets())
        self.assertEqual(ci.select([".github/workflows/ci.yml"]), ci.all_targets())

    def test_missing_yaml_support_selects_everything(self):
        with patch.dict("sys.modules", {"yaml": None}):
            self.assertIsNone(ci.targets_for_workflow(WORKFLOW, WORKFLOW))

    def test_shared_change_wins_over_scoped_job_change(self):
        self.assertEqual(ci.select([".github/workflows/ci.yml", "scripts/ci-changes.py"], ["dart", "flutter"]),
                         ci.all_targets())

    def test_mapping_targets_exist_and_jobs_are_declared(self):
        targets = set(ci.all_targets())
        jobs = yaml.safe_load((ROOT / ".github/workflows/ci.yml").read_text())["jobs"]
        for mapping in (ci.SCRIPT_TARGETS, ci.JOB_TARGETS):
            for key, owners in mapping.items():
                with self.subTest(key=key):
                    self.assertTrue(owners)
                    self.assertLessEqual(set(owners), targets)
        self.assertLessEqual(ci.JOB_TARGETS.keys(), jobs.keys())
        for script in ci.SCRIPT_TARGETS:
            self.assertTrue((ROOT / script).is_file())

    def test_reads_workflows_at_git_revisions_and_handles_missing_history(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True).strip()
            git("init", "-q")
            workflow = root / ".github/workflows/ci.yml"
            workflow.parent.mkdir(parents=True)
            workflow.write_text(WORKFLOW)
            git("add", ".")
            git("-c", "user.name=Sample", "-c", "user.email=sample@example.test", "commit", "-qm", "initial")
            before = git("rev-parse", "HEAD")
            workflow.write_text(WORKFLOW.replace("sample-check", "sample-check-updated"))
            git("add", ".")
            git("-c", "user.name=Sample", "-c", "user.email=sample@example.test", "commit", "-qm", "update")
            after = git("rev-parse", "HEAD")
            with patch.object(ci, "ROOT", root):
                self.assertEqual(ci.workflow_targets_at(before, after), ["dart", "flutter"])
                self.assertIsNone(ci.workflow_targets_at("sample-missing-ref", after))


if __name__ == "__main__":
    unittest.main()
