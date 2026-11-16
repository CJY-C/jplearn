#!/usr/bin/env python3
"""Compile explicit, stable content records. No IDs are inferred from array order."""
import argparse
import copy
import json
from pathlib import Path
from word_links import lexical_words, validate_lexemes

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Sources/LearningCore/Resources/foundation.json"
COLLECTIONS = ("items", "sentences", "exercises", "lessons", "readings", "introModules")


def make_pack(overrides=None, *, include_pronunciation=True):
    overrides = overrides or {}
    pack = json.loads((ROOT / "content/catalog.json").read_text())
    for key in COLLECTIONS:
        path = ROOT / "content/legacy" / (key + ".json")
        pack[key] = json.loads(path.read_text()) if path.exists() else []
    paths = set((ROOT / "content/batches").glob("*.json")) | set(overrides)
    for path in sorted(paths):
        batch = overrides[path] if path in overrides else json.loads(path.read_text())
        for key in COLLECTIONS:
            pack[key].extend(copy.deepcopy(batch.get(key, [])))
    pronunciation_source = json.loads((ROOT / "content/manuscripts.json").read_text()).get("pronunciationSource")
    if include_pronunciation and pronunciation_source:
        assert Path(pronunciation_source).name == pronunciation_source, "Use a sibling pronunciation source"
        pronunciation_path = ROOT / "content" / pronunciation_source
        pronunciation = json.loads(pronunciation_path.read_text())
        assert pronunciation["version"] == 1
        pack["introModules"].extend(copy.deepcopy(pronunciation["introModules"]))
        words = {item["id"]: item for item in pack["items"]}
        for identifier, accents in pronunciation["wordAccents"].items():
            assert identifier in words and words[identifier]["kind"] == "word", identifier
            assert "pitchAccents" not in words[identifier], (identifier, "duplicate pitch annotation")
            words[identifier]["pitchAccents"] = copy.deepcopy(accents)
    # Keep each batch's authored order within a level, while preventing a legacy
    # N3 lesson from being recommended ahead of newly added N5 foundations.
    stage_order = {s["id"].upper(): index for index, s in enumerate(pack["stages"])}
    pack["lessons"].sort(key=lambda lesson: stage_order[lesson["level"]])
    validate(pack)
    return pack


def validate(pack):
    groups = {}
    for key in COLLECTIONS:
        records = pack[key]
        groups[key] = {r["id"]: r for r in records}
        if len(groups[key]) != len(records): raise ValueError(f"Duplicate IDs in {key}")
    references = {r["id"]: r for r in pack["references"]}
    validate_lexemes(pack["items"])
    for word in pack["items"]:
        for accent in word.get("pitchAccents", []):
            assert word["kind"] == "word" and accent["reading"] in [word["reading"]] + word.get("acceptedReadings", []), word["id"]
            assert isinstance(accent["morae"], list) and accent["morae"] and all(isinstance(m, str) and m for m in accent["morae"]), word["id"]
            assert "".join(accent["morae"]) == accent["reading"], word["id"]
            assert type(accent["dropAfter"]) is int and 0 <= accent["dropAfter"] <= len(accent["morae"]), word["id"]
            assert accent["dialect"] and accent["citations"], word["id"]
            for citation in accent["citations"]:
                assert citation["sourceID"] in references and citation["locator"] and citation["status"] in {"reference", "sourceChecked"}, citation
        if owner := word.get("lexemeID"):
            assert owner in word.get("prerequisiteIDs", []), (word["id"], "sense needs its base word")
            levels = ["N5", "N4", "N3", "N2"]
            assert levels.index(groups["items"][owner]["level"]) <= levels.index(word["level"]), (word["id"], "sense taught before its word")
            examples = [groups["sentences"][sid] for sid in word.get("exampleSentenceIDs", [])]
            assert len({"".join(s["text"] for s in e["segments"]) for e in examples}) >= 2, (word["id"], "sense needs distinct contexts")
            assert all(any(s.get("itemID") == word["id"] for s in e["segments"]) for e in examples), (word["id"], "sense example points to a different meaning")
    for key in COLLECTIONS:
        for record in pack[key]:
            for c in record.get("citations", []):
                assert c["sourceID"] in references and c["locator"], c
                assert c["status"] in {"reference", "adapted", "translated", "sourceChecked", "original"}, c
    for reading in pack["readings"]:
        assert reading["sentenceIDs"] and set(reading["sentenceIDs"]) <= groups["sentences"].keys()
        for question in reading.get("questions", []):
            assert 2 <= len(question["choices"]) <= 4
            assert len(set(question["choices"])) == len(question["choices"])
            assert question["answerIndex"] in range(len(question["choices"]))
            assert question["evidenceSentenceIDs"] and set(question["evidenceSentenceIDs"]) <= set(reading["sentenceIDs"])
        if "paragraphs" in reading:
            assert [sid for p in reading["paragraphs"] for sid in p["sentenceIDs"]] == reading["sentenceIDs"]
            assert [w for p in reading["paragraphs"] for w in p["vocabulary"]] == reading["vocabulary"]
    for key in ("items", "lessons"):
        visited, active = set(), set()
        def visit(identifier):
            if identifier in active: raise ValueError(f"Prerequisite cycle: {identifier}")
            if identifier in visited: return
            active.add(identifier)
            for required in groups[key][identifier].get("prerequisiteIDs", []): visit(required)
            active.remove(identifier); visited.add(identifier)
        for identifier in groups[key]: visit(identifier)


def report(pack):
    return {"version": pack["version"], "words": len(lexical_words(pack["items"])),
            "wordTargets": sum(i["kind"] == "word" for i in pack["items"]),
            "knowledgePoints": sum(i["kind"] == "grammar" for i in pack["items"]),
            "exercises": len(pack["exercises"]), "readings": len(pack["readings"]),
            "assessments": sum(r.get("purpose") == "assessment" for r in pack["readings"]),
            "introModules": len(pack["introModules"]),
            "independentlyReviewed": sum(i["status"] == "reviewed" for i in pack["items"])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    pack = make_pack()
    output = json.dumps(pack, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != output: raise SystemExit("Generated course is stale; run python3 scripts/build_content.py")
    else: OUTPUT.write_text(output)
    print(json.dumps(report(pack), ensure_ascii=False))


if __name__ == "__main__": main()
