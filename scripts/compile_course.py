#!/usr/bin/env python3
"""Compile the registered manuscripts with a complete current word index.

Word batches are compiled twice in memory so cross-batch links do not depend on
file order or stale generated data. Validate the complete replacement pack before
writing any output; --check only reads files.
"""
import argparse
import json
from pathlib import Path

from build_content import ROOT, make_pack
from compile_grammar import compile_manuscript as grammar
from compile_readings import compile_manuscript as reading
from compile_words import compile_manuscript as word

COMPILERS = {"grammar": grammar, "reading": reading, "word": word}


def entries():
    manifest = json.loads((ROOT / "content/manuscripts.json").read_text())
    assert manifest["version"] == 1
    records = manifest["entries"]
    for field in ("source", "batch"):
        values = [r[field] for r in records]
        assert len(values) == len(set(values)), f"Duplicate manuscript {field}"
        assert all(Path(v).name == v for v in values), "Use sibling file names"
    assert all(r["kind"] in COMPILERS for r in records)
    actual_sources = {p.name for p in (ROOT / "content/authoring").glob("*.tsv")}
    assert {r["source"] for r in records} == actual_sources, "Unregistered or missing manuscript"
    allowed_batches = {r["batch"] for r in records} | set(manifest["staticBatches"])
    actual_batches = {p.name for p in (ROOT / "content/batches").glob("*.json")}
    assert actual_batches <= allowed_batches, "Unregistered generated batch"
    assert set(manifest["staticBatches"]) <= actual_batches, "Missing static batch"
    return records


def compile_all():
    records = entries()
    # Compile from authored/static records; stale managed JSON must not provide
    # phantom targets or prevent regeneration. All replacements validate later.
    index = make_pack(overrides={ROOT / "content/batches" / r["batch"]: {} for r in records})
    outputs = {}

    def compile_one(record):
        result = COMPILERS[record["kind"]](ROOT / "content/authoring" / record["source"], index)
        batch = result[0] if record["kind"] == "grammar" else result
        outputs[ROOT / "content/batches" / record["batch"]] = batch
        ids = {i["id"] for i in batch.get("items", [])}
        index["items"] = [i for i in index["items"] if i["id"] not in ids] + batch.get("items", [])

    for _ in range(2):
        for record in records:
            if record["kind"] == "word": compile_one(record)
    for record in records:
        if record["kind"] != "word": compile_one(record)
    make_pack(overrides=outputs)
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    outputs = compile_all()
    for path, batch in outputs.items():
        text = json.dumps(batch, ensure_ascii=False, indent=2) + "\n"
        if args.check:
            assert path.exists() and path.read_text() == text, f"Stale manuscript batch: {path.name}"
        else:
            path.write_text(text)
    print(f'{len(outputs)} manuscript batches {"checked" if args.check else "compiled"}.')


if __name__ == "__main__": main()
