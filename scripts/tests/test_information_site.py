import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]


class InformationSiteTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        root = pathlib.Path(self.scratch.name)
        self.script = root / 'repo/scripts/generate-information-site.py'
        self.script.parent.mkdir(parents=True)
        shutil.copyfile(REPO / 'scripts/generate-information-site.py', self.script)
        self.documents = root / 'repo/OpenWorkRemote/Resources/Information'
        shutil.copytree(REPO / 'OpenWorkRemote/Resources/Information', self.documents)
        self.output = root / 'site'

    def generate(self, *args):
        return subprocess.run([sys.executable, str(self.script), '--output', str(self.output), *args],
                              capture_output=True, text=True)

    def test_regeneration_removes_only_the_retired_policy_page(self):
        retired = self.output / 'privacy/openwork-beta/index.html'
        retired.parent.mkdir(parents=True)
        retired.write_text('Earlier policy that must no longer be available')
        unrelated = self.output / 'assets/keep.txt'
        unrelated.parent.mkdir()
        unrelated.write_text('Keep unrelated site assets')
        result = self.generate('--allow-draft')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(retired.exists())
        self.assertEqual(unrelated.read_text(), 'Keep unrelated site assets')

    def test_unapproved_copy_cannot_change_a_publishable_output(self):
        manifest_path = self.documents / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['policyApproved'] = False
        manifest_path.write_text(json.dumps(manifest))
        self.output.mkdir()
        existing = self.output / 'index.html'
        existing.write_text('Existing published copy')
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Policy approval is required', result.stderr)
        self.assertEqual(existing.read_text(), 'Existing published copy')

    def test_draft_is_deterministic_and_has_no_retired_policy_route_or_link(self):
        self.assertEqual(self.generate('--allow-draft').returncode, 0)
        def snapshot():
            return {str(p.relative_to(self.output)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in self.output.rglob('*') if p.is_file()}
        first = snapshot()
        self.assertEqual(self.generate('--allow-draft').returncode, 0)
        self.assertEqual(snapshot(), first)
        pages = list(self.output.rglob('*.html'))
        self.assertEqual(len(pages), 5)
        for page in pages:
            content = page.read_text()
            self.assertNotIn('openwork-beta', content)
            self.assertIn('not approved for publication', content)


if __name__ == '__main__':
    unittest.main()
