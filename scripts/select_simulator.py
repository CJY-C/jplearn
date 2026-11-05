#!/usr/bin/env python3
"""Use an SE3-sized simulator for both persistence and interaction regressions."""
import json
import subprocess


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()


devices = json.loads(simctl("list", "devices", "available", "--json"))["devices"]
for runtime, entries in devices.items():
    if "iOS-18-5" in runtime:
        for device in entries:
            if device["name"] in {"iPhone SE (3rd generation)", "JPLearn SE3"} and device["isAvailable"]:
                print(device["udid"])
                raise SystemExit(0)
types = json.loads(simctl("list", "devicetypes", "--json"))["devicetypes"]
device_type = next(item["identifier"] for item in types if item["name"] == "iPhone SE (3rd generation)")
runtimes = json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
runtime = next(item["identifier"] for item in runtimes if item["version"] == "18.5" and item["isAvailable"])
print(simctl("create", "JPLearn SE3", device_type, runtime))
