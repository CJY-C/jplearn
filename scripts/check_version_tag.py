#!/usr/bin/env python3
"""Reject version tags that do not identify the app being built."""
import os
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def validate_version(config, ref_type, ref_name):
    versions = re.findall(r"^MARKETING_VERSION\s*=\s*(\S+)\s*$", config, re.MULTILINE)
    if len(versions) != 1 or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", versions[0]):
        raise ValueError("Version.xcconfig must declare exactly one X.Y.Z MARKETING_VERSION")
    version = versions[0]
    if ref_type not in {"branch", "tag"} or not ref_name:
        raise ValueError("GITHUB_REF_TYPE and GITHUB_REF_NAME must identify a branch or tag")
    if ref_type == "tag" and ref_name != f"v{version}":
        raise ValueError(f"Tag {ref_name!r} does not match app version v{version}")
    return version


if __name__ == "__main__":
    try:
        version = validate_version((ROOT / "Version.xcconfig").read_text(),
                                   os.environ.get("GITHUB_REF_TYPE", ""),
                                   os.environ.get("GITHUB_REF_NAME", ""))
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    print(f"Validated app version {version}")
