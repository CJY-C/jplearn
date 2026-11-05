#!/usr/bin/env python3
import re
import sys
from pathlib import Path

version = sys.argv[1]
assert re.fullmatch(r"\d+\.\d+\.\d+", version), "Invalid release version"
text = Path("CHANGELOG.md").read_text()
match = re.search(r"^## " + re.escape(version) + r"\s*\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL)
if not match:
    raise SystemExit(f"Add release notes for {version} to CHANGELOG.md before publishing")
print(match.group(1).strip())
