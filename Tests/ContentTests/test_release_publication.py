import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleasePublicationTests(unittest.TestCase):
    def publish(self, existing=False, ref="refs/tags/v1.2.3"):
        with tempfile.TemporaryDirectory() as location:
            folder = Path(location)
            binary = folder / "bin"
            binary.mkdir()
            (binary / "python3").symlink_to(sys.executable)
            fake = binary / "gh"
            fake.write_text("#!" + sys.executable + "\n" +
                "import json,os,sys\n" +
                "args=sys.argv[1:]\n" +
                "if args[:2]==['release','view']:\n" +
                " sys.exit(0 if os.environ['TEST_RELEASE_EXISTS']=='1' else 1)\n" +
                "if args[:2]!=['release','create']: sys.exit(2)\n" +
                "open(os.environ['TEST_RELEASE_ARGS'],'w').write(json.dumps(args))\n")
            fake.chmod(0o755)
            (folder / "scripts").mkdir()
            shutil.copyfile(ROOT / "scripts/release_notes.py", folder / "scripts/release_notes.py")
            (folder / "CHANGELOG.md").write_text("# Changes\n\n## 1.2.3\n\n- New behavior.\n")
            artifact = folder / "build/release/JPLearn.ipa"
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b"unchanged fixture artifact")
            log = folder / "create-args.json"
            env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ.get("PATH", ""),
                GH_REPO="example/jplearn-tests", APP_VERSION="1.2.3", RELEASE_COMMIT="a" * 40,
                RELEASE_REF=ref, TEST_RELEASE_EXISTS="1" if existing else "0", TEST_RELEASE_ARGS=str(log))
            result = subprocess.run(["bash", str(ROOT / "scripts/publish_release.sh")],
                cwd=folder, env=env, text=True, capture_output=True)
            return result, json.loads(log.read_text()) if log.exists() else None, artifact.read_bytes()

    def test_existing_release_is_kept_without_uploading_or_replacing_assets(self):
        result, args, artifact = self.publish(existing=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(args)
        self.assertEqual(artifact, b"unchanged fixture artifact")
        self.assertIn("keeping its original assets", result.stdout)

    def test_new_release_uses_the_tested_commit_tag_and_ipa(self):
        result, args, _ = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(args[:4], ["release", "create", "v1.2.3", "build/release/JPLearn.ipa"])
        self.assertEqual(args[args.index("--target") + 1], "a" * 40)
        self.assertEqual(args[args.index("--repo") + 1], "example/jplearn-tests")
        self.assertIn("--notes-file", args)

    def test_mismatched_tag_cannot_publish_a_different_app_version(self):
        result, args, _ = self.publish(ref="refs/tags/v9.9.9")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(args)
        self.assertIn("Tag does not match app version", result.stderr)


if __name__ == "__main__": unittest.main()
