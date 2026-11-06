#!/usr/bin/env python3
"""Report actual N5–N2 delivery against the agreed complete-course requirements.

The audit cannot certify language correctness. It checks explicit mappings and
evidence links, counts real distinct contexts, and never treats planned content
or a compiler's success as shipped curriculum. --require-complete is the final
delivery gate; without it an incomplete course can still be inspected.
"""
import argparse
from collections import Counter, defaultdict
import json
import math

from build_content import ROOT, make_pack

LEVELS = ["N5", "N4", "N3", "N2"]


def audit(pack, syllabus, reference):
    items = {i["id"]: i for i in pack["items"]}
    sentences = {s["id"]: s for s in pack["sentences"]}
    requirements = {f'{p["level"]}:{p["id"]}': p for p in reference["patterns"]}
    mappings = syllabus["grammarCoverage"]
    errors = []
    heldout_ids = {sid for reading in pack["readings"] if reading.get("purpose") == "assessment" for sid in reading["sentenceIDs"]}
    heldout_texts = {"".join(x["text"] for x in sentences[sid]["segments"]) for sid in heldout_ids}
    practice_ids = {sid for item in pack["items"] for sid in item.get("exampleSentenceIDs", [])}
    practice_ids.update(e["sentenceID"] for e in pack["exercises"])
    practice_ids.update(sid for lesson in pack["lessons"] for sid in lesson["sentenceIDs"])
    practice_ids.update(sid for reading in pack["readings"] if reading.get("purpose") != "assessment" for sid in reading["sentenceIDs"])
    for sid in sorted(practice_ids):
        if sid in heldout_ids or "".join(x["text"] for x in sentences[sid]["segments"]) in heldout_texts:
            errors.append(f"Held-out sentence leaked to practice: {sid}")
    exercises = defaultdict(list)
    for exercise in pack["exercises"]: exercises[exercise["targetID"]].append(exercise)
    for key in mappings:
        if key not in requirements: errors.append(f"Unknown grammar requirement: {key}")
    grammar_covered = Counter()
    missing = defaultdict(list)
    for key, requirement in requirements.items():
        mapping = mappings.get(key)
        valid = bool(mapping and mapping.get("itemIDs") and mapping.get("note"))
        if valid:
            for gid in mapping["itemIDs"]:
                item = items.get(gid)
                if not item or item["kind"] != "grammar":
                    errors.append(f"{key}: missing grammar item {gid}"); valid = False; continue
                if LEVELS.index(item["level"]) > LEVELS.index(requirement["level"]):
                    errors.append(f"{key}: {gid} is taught after the required level"); valid = False
                # Distinct IDs containing the same sentence are one context, not six.
                texts = {"".join(x["text"] for x in sentences[e["sentenceID"]]["segments"])
                         for e in exercises[gid] if e.get("skill", "grammar") == "grammar"}
                if len(texts) < syllabus["minimumGrammarContexts"]:
                    errors.append(f"{key}: {gid} has only {len(texts)} distinct contexts"); valid = False
        if valid: grammar_covered[requirement["level"]] += 1
        else: missing[requirement["level"]].append(key)
    word_context_gaps = []
    for item in pack["items"]:
        if item["kind"] != "word": continue
        texts = {"".join(x["text"] for x in sentences[sid]["segments"])
                 for sid in item.get("exampleSentenceIDs", []) if sid in sentences}
        if len(texts) < syllabus["minimumWordContexts"]: word_context_gaps.append(item["id"])
    stages = []
    for target in syllabus["levels"]:
        level = target["level"]
        readings = [r for r in pack["readings"] if r["level"] == level]
        actual = dict(words=sum(i["kind"] == "word" and i["level"] == level for i in items.values()),
            knowledgePoints=sum(i["kind"] == "grammar" and i["level"] == level for i in items.values()),
            readings=len(readings), lessons=sum(l["level"] == level for l in pack["lessons"]),
            assessments=sum(r.get("purpose") == "assessment" for r in readings))
        expected = {key: target[key] for key in actual if key in target}
        expected["assessments"] = math.ceil(target["readings"] * syllabus["assessmentFraction"])
        deficits = {key: expected[key] - actual[key] for key in expected if actual[key] < expected[key]}
        grammar_total = sum(r["level"] == level for r in requirements.values())
        stages.append(dict(level=level, actual=actual, required=expected, deficits=deficits,
            grammarPatterns=dict(covered=grammar_covered[level], required=grammar_total, missing=missing[level]),
            complete=not deficits and not missing[level]))
    bridges = []
    for bridge in syllabus["readingBridges"]:
        ids = bridge["readingIDs"]
        found = [r for r in pack["readings"] if r["id"] in ids and r["level"] == "N2"]
        complete = len(found) >= bridge["minimumReadings"] and len(found) == len(ids)
        bridges.append(dict(id=bridge["id"], title=bridge["title"], actual=len(found),
            required=bridge["minimumReadings"], complete=complete))
    return dict(complete=all(s["complete"] for s in stages) and all(b["complete"] for b in bridges)
                and not errors and not word_context_gaps,
        stages=stages, readingBridges=bridges, wordContextGaps=word_context_gaps, errors=errors,
        languageReview="未独立语言审校；本报告验证课程覆盖及数据结构，不能证明翻译或题目没有语言错误。")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-complete", action="store_true")
    parser.add_argument("--output", type=str)
    args = parser.parse_args()
    result = audit(make_pack(), json.loads((ROOT / "content/syllabus.json").read_text()),
        json.loads((ROOT / "content/reference/openjlpt-grammar.json").read_text()))
    output = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output: (ROOT / args.output).write_text(output)
    print(output, end="")
    if result["errors"] or (args.require_complete and not result["complete"]): raise SystemExit(1)


if __name__ == "__main__": main()
