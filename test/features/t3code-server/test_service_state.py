#!/usr/bin/env python3
# relationships:
#   verifies: t3code-server

import json
import hashlib
import os
import shlex
import shutil
from pathlib import Path
import subprocess
import tempfile
import tarfile
import unittest

FEATURE = Path(__file__).parents[3] / 'src/features/t3code-server'


class RuntimeStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.runtime = self.home / '.t3/runtime'
        self.runtime.mkdir(parents=True)
        config = self.home / 'config.env'
        import pwd
        user = pwd.getpwuid(os.getuid()).pw_name
        config.write_text(f'T3CODE_SERVER_USER={user}\nT3CODE_SERVER_HOME={self.home}\n')
        self.env = {**os.environ, 'T3CODE_SERVER_CONFIG': str(config)}

    def run_runtime(self, *args, success=True):
        result = subprocess.run(['bash', str(FEATURE / 't3code-runtime'), *args], env=self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def install(self, version, native=True):
        directory = self.runtime / 'versions' / version
        directory.mkdir(parents=True)
        entry = directory / 't3'
        response = json.dumps({'status': 'ready', 'version': version, 'launcherProtocol': 3})
        entry.write_text(f"#!/bin/sh\necho '{response}'\n" if native else '#!/bin/sh\nexit 1\n')
        entry.chmod(0o755)
        (directory / '.install-complete').write_text(version)
        return directory

    def test_native_selection_and_cli_follow_committed_active_version(self):
        self.install('1.2.3')
        self.install('1.2.4')
        self.run_runtime('select', '1.2.3')
        state = self.runtime / 'service-state.json'
        self.assertEqual(json.loads(state.read_text()), {'protocol': 3, 'activeVersion': '1.2.3'})
        launcher = self.runtime / 'service-launcher'
        self.assertEqual(launcher.resolve(), self.runtime / 'versions/1.2.3/t3')
        self.assertIn(str(launcher), (self.runtime / 'launchers').read_text())
        state.write_text(json.dumps({'protocol': 3, 'activeVersion': '1.2.4'}))
        # A stale legacy selector must never undo a native update after restart.
        (self.runtime / 'selected-version').write_text('1.2.3')
        self.run_runtime('bootstrap')
        self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.4')
        self.assertEqual(self.run_runtime('selected-entry').stdout.strip(), str(self.runtime / 'versions/1.2.4/t3'))
        self.assertEqual(launcher.resolve(), self.runtime / 'versions/1.2.3/t3')

    def test_legacy_pin_and_local_downgrade_still_work(self):
        self.install('1.2.3')
        self.install('1.2.2', native=False)
        self.run_runtime('select', '1.2.3')
        self.run_runtime('select', '1.2.2')
        self.assertFalse((self.runtime / 'service-state.json').exists())
        self.assertFalse((self.runtime / 'service-launcher').exists())
        self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.2')

    def test_corrupt_state_fails_closed_including_entry_and_bootstrap(self):
        (self.runtime / 'selected-version').write_text('1.2.3')
        path = self.runtime / 'service-state.json'
        for value in ('{', '[]', '{"protocol":4,"activeVersion":"1.2.3"}', '{"protocol":3,"activeVersion":"../../sample"}'):
            path.write_text(value)
            for command in ('selected-version', 'selected-entry', 'bootstrap'):
                with self.subTest(value=value, command=command):
                    self.run_runtime(command, success=False)
                    self.assertEqual(path.read_text(), value)

    def queue(self, version):
        directory = self.install(version)
        stage = directory.parent / '.staging-sample'
        directory.rename(stage)
        (stage / '.maintenance-version').write_text(version)
        origin = self.run_runtime('selected-version').stdout.strip()
        (self.runtime / 'queued-runtime').write_text(f'{version}\n{stage}\n{origin}\n')
        return stage

    def test_deferred_runtime_applies_only_at_boot_and_recovers_interrupted_move(self):
        self.install('1.2.3')
        self.run_runtime('select', '1.2.3')
        stage = self.queue('1.2.4')
        self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.3')
        # Simulate interruption between publishing the runtime and selecting it.
        stage.rename(self.runtime / 'versions/1.2.4')
        self.run_runtime('bootstrap')
        self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.4')
        self.assertFalse((self.runtime / 'queued-runtime').exists())
        self.run_runtime('bootstrap')

    def test_pending_native_recovery_takes_precedence_over_local_queue(self):
        self.install('1.2.3')
        self.run_runtime('select', '1.2.3')
        path = self.runtime / 'service-state.json'
        state = {'protocol': 3, 'activeVersion': '1.2.3', 'update': {'id': 'sample-update', 'status': 'pending', 'fromVersion': '1.2.3', 'targetVersion': '1.2.4', 'dbPath': '/tmp/sample.sqlite'}}
        path.write_text(json.dumps(state))
        self.queue('1.2.5')
        self.run_runtime('bootstrap')
        self.assertEqual(json.loads(path.read_text()), state)
        self.assertTrue((self.runtime / 'queued-runtime').exists())
        self.install('1.2.6')
        self.run_runtime('select', '1.2.6', success=False)

    def test_incomplete_runtime_cannot_be_selected(self):
        directory = self.install('1.2.3')
        (directory / '.install-complete').write_text('1.2.4')
        self.run_runtime('select', '1.2.3', success=False)
        self.assertFalse((self.runtime / 'service-state.json').exists())

    def test_bad_queue_cannot_replace_the_active_runtime(self):
        self.install('1.2.3')
        self.run_runtime('select', '1.2.3')
        stage = self.queue('1.2.4')
        queue = self.runtime / 'queued-runtime'
        for contents in ('1.2.4\n', f'../../sample\n{stage}\n1.2.3\n', f'1.2.4\n{self.home}/sample\n1.2.3\n', f'1.2.4\n{stage}\n1.2.3\nsample-extra\n'):
            queue.write_text(contents)
            self.run_runtime('bootstrap', success=False)
            self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.3')
        queue.write_text(f'1.2.4\n{stage}\n1.2.3\n')
        (stage / '.maintenance-version').write_text('1.2.5')
        self.run_runtime('bootstrap', success=False)
        self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.3')

    def test_queue_path_guard_has_an_otherwise_valid_runtime(self):
        self.install('1.2.3')
        self.run_runtime('select', '1.2.3')
        stage = self.queue('1.2.4')
        external = self.home / 'sample-runtime'
        stage.rename(external)
        (self.runtime / 'queued-runtime').write_text(f'1.2.4\n{external}\n1.2.3\n')
        self.run_runtime('bootstrap', success=False)
        self.assertTrue(external.exists())
        self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.3')

    def test_queue_rejects_traversal_even_with_a_valid_staging_prefix(self):
        self.install('1.2.3')
        self.run_runtime('select', '1.2.3')
        stage = self.queue('1.2.4')
        external = self.runtime / 'sample-runtime'
        stage.rename(external)
        (self.runtime / 'versions/.staging-sample').mkdir()
        traversal = self.runtime / 'versions/.staging-sample/../../sample-runtime'
        (self.runtime / 'queued-runtime').write_text(f'1.2.4\n{traversal}\n1.2.3\n')
        self.run_runtime('bootstrap', success=False)
        self.assertTrue(external.exists())

    def test_native_commit_expires_a_deferred_local_downgrade(self):
        self.install('1.2.3')
        self.install('1.2.4')
        self.run_runtime('select', '1.2.3')
        stage = self.queue('1.2.2')
        state = {'protocol': 3, 'activeVersion': '1.2.4', 'update': {'id': 'sample-update', 'status': 'committed', 'fromVersion': '1.2.3', 'targetVersion': '1.2.4'}}
        path = self.runtime / 'service-state.json'
        path.write_text(json.dumps(state))
        result = self.run_runtime('bootstrap')
        self.assertIn('Discarding queued 1.2.2', result.stderr)
        self.assertEqual(json.loads(path.read_text()), state)
        self.assertFalse(stage.exists())
        self.assertFalse((self.runtime / 'queued-runtime').exists())

    def test_cached_runtime_preparation_keeps_live_files_untouched(self):
        directory = self.install('1.2.3')
        self.run_runtime('select', '1.2.3')
        before = (directory / 't3').read_bytes()
        self.run_runtime('prepare-installed', '1.2.3')
        self.assertEqual((directory / 't3').read_bytes(), before)
        self.run_runtime('bootstrap')
        self.assertEqual(self.run_runtime('selected-version').stdout.strip(), '1.2.3')

    def test_legacy_preflight_failure_is_explained(self):
        self.install('1.2.3', native=False)
        result = self.run_runtime('select', '1.2.3')
        self.assertIn('preflight did not pass', result.stderr)
        self.assertIn('exit 1', result.stderr)

    def test_ready_preflight_with_stderr_warning_still_uses_launcher(self):
        directory = self.install('1.2.3')
        entry = directory / 't3'
        entry.write_text(entry.read_text().replace('#!/bin/sh\n', '#!/bin/sh\necho sample-warning >&2\n'))
        result = self.run_runtime('select', '1.2.3')
        self.assertEqual(json.loads((self.runtime / 'service-state.json').read_text())['activeVersion'], '1.2.3')
        self.assertIn('sample-warning', result.stderr)

    def test_status_reports_installed_versions_despite_missing_or_corrupt_selection(self):
        self.install('1.2.3')
        script = self.home / 'sample-update'
        library = self.home / 'sample-library'
        library.mkdir()
        for file in ('t3code-runtime', 'service-state.py'):
            shutil.copyfile(FEATURE / file, library / file)
        # Match the executable mode assigned by install.sh, not the source mode.
        (library / 't3code-runtime').chmod(0o755)
        source = (FEATURE / 't3code-server-update').read_text()
        script.write_text(source.replace('lib_dir=/usr/local/lib/t3code-server', f'lib_dir={shlex.quote(str(library))}'))
        for state in (None, '{'):
            if state is not None:
                (self.runtime / 'service-state.json').write_text(state)
            result = subprocess.run(['bash', str(script), '--status'], env=self.env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('selected version: unavailable', result.stdout)
            self.assertIn('installed versions:\n  1.2.3', result.stdout)
            self.assertIn('service:', result.stdout)

    def test_preparation_never_replaces_live_runtime_and_cleans_superseded_queue(self):
        directory = self.install('1.2.3')
        self.run_runtime('select', '1.2.3')
        original = (directory / 't3').read_bytes()
        package = self.home / 'sample-package'
        package.mkdir()
        entry = package / 't3'
        entry.write_bytes(original + b'# sample replacement\n')
        entry.chmod(0o755)
        archive = self.home / 'sample-runtime.tar.gz'
        with tarfile.open(archive, 'w:gz') as stream:
            stream.add(package, arcname='sample-runtime')
        checksums = self.home / 'SHA256SUMS'
        checksums.write_text(f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n')
        args = ('prepare-archive', '1.2.3', archive.as_uri(), checksums.as_uri())
        self.run_runtime(*args)
        queued = self.runtime / 'queued-runtime'
        first_stage = Path(queued.read_text().splitlines()[1])
        self.assertEqual((directory / 't3').read_bytes(), original)
        self.run_runtime(*args)
        self.assertFalse(first_stage.exists())
        self.assertEqual((directory / 't3').read_bytes(), original)
        last_queue = queued.read_text()
        checksums.write_text(f'{"0" * 64}  {archive.name}\n')
        self.run_runtime(*args, success=False)
        self.assertEqual(queued.read_text(), last_queue)
        self.assertEqual(len(list((self.runtime / 'versions').glob('.staging-*'))), 1)
        self.run_runtime('bootstrap')
        self.assertEqual((directory / 't3').read_bytes(), entry.read_bytes())


if __name__ == '__main__':
    unittest.main()
