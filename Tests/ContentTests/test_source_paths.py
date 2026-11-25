import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SourcePathTests(unittest.TestCase):
    def test_review_hash_inputs_are_available_in_an_independent_checkout(self):
        for ledger in (ROOT / "content/source-checks").glob("*.json"):
            data = json.loads(ledger.read_text())
            for name in data.get("reviewSHA256", {}):
                with self.subTest(ledger=ledger.name, path=name):
                    path = Path(name)
                    self.assertFalse(path.is_absolute(), "Review paths must not depend on the author's machine")
                    target = (ROOT / path).resolve()
                    self.assertTrue(target.is_relative_to(ROOT), "Review inputs must stay inside the repository")
                    self.assertTrue(target.is_file(), "Review inputs must be included in the checkout")


if __name__ == "__main__": unittest.main()
