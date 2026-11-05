#!/usr/bin/env python3
"""Fail packaging if the built app loses its legacy deployment target/resources."""
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
with (app / "Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
assert info["MinimumOSVersion"] == "15.5", info.get("MinimumOSVersion")
assert info["CFBundleIdentifier"] == "dev.jplearn.reader"
assert (app / info["CFBundleExecutable"]).is_file(), "Missing executable"
assert list(app.rglob("foundation.json")), "Course resource missing"
assert list(app.rglob("ThirdPartyNotices.txt")), "Third-party license notice missing"
print("Archive: iOS 15.5 target, executable and bundled course verified.")
