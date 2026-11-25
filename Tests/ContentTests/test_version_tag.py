from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from check_version_tag import validate_version


class VersionTagTests(unittest.TestCase):
    config = "MARKETING_VERSION = 0.20.0\nCURRENT_PROJECT_VERSION = 27\n"

    def test_matching_version_tag_and_manual_branch_are_accepted(self):
        for kind, name in [("tag", "v0.20.0"), ("branch", "main"),
                           ("branch", "curriculum/n3-similarity-and-tendencies")]:
            with self.subTest(kind=kind, name=name):
                self.assertEqual(validate_version(self.config, kind, name), "0.20.0")

    def test_wrong_version_or_non_version_tag_cannot_build_a_mislabeled_ipa(self):
        for name in ["v0.19.0", "v0.20.1", "0.20.0", "v0.20.0-beta", "v1-anything"]:
            with self.subTest(name=name):
                with self.assertRaises(ValueError): validate_version(self.config, "tag", name)

    def test_ambiguous_version_or_missing_ref_is_rejected(self):
        for config, kind, name in [("", "tag", "v0.20.0"),
                                   (self.config * 2, "tag", "v0.20.0"),
                                   ("MARKETING_VERSION = invalid\n", "branch", "main"),
                                   (self.config, "", "v0.20.0"),
                                   (self.config, "tag", "")]:
            with self.subTest(config=config, kind=kind, name=name):
                with self.assertRaises(ValueError): validate_version(config, kind, name)


if __name__ == "__main__": unittest.main()
