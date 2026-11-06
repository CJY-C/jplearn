#!/usr/bin/env python3
"""Compile explicitly keyed, human-editable grammar manuscripts into course batches.

H: optional explicit course level (legacy manuscripts default to N5).
G: id, title, reading, romaji, meaning, rule, prerequisites, reference patterns.
   An optional final field links a practice passage to the unit.
C: target id, stable context key, ruby text, translation, prompt, answer,
   two distractors, explanation. TSV fields never contain literal tabs/newlines.
B: target id, additional reference source id, precise reference locator.
No network, NLP, generated prose or inferred content IDs are used at build time.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

from build_content import ROOT, make_pack
from word_links import resolve_word

RUBY = re.compile(r"\[([^|\]]+)\|([^|\]]+)(?:\|([^\]]+))?\]")
KANJI = re.compile(r"[一-龯]")


def compile_manuscript(path, pack):
    words = {w["text"]: w for w in pack["items"] if w["kind"] == "word"}
    groups, contexts, bibliography = {}, {}, {}
    level, has_header = "N5", False
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if not line or line.startswith("#"): continue
        fields = line.split("\t")
        try:
            if fields[0] == "H":
                _, level = fields
                assert not has_header and not groups and not contexts and not bibliography
                assert level in ("N5", "N4", "N3", "N2")
                has_header = True
            elif fields[0] == "G":
                assert len(fields) in [9, 10], "expected 9 or 10 grammar fields"
                _, gid, title, reading, romaji, meaning, rule, required, patterns = fields[:9]
                assert gid not in groups, f"duplicate grammar: {gid}"
                groups[gid] = dict(id=gid, title=title, reading=reading, romaji=romaji,
                    meaning=meaning, rule=rule, required=required.split(",") if required else [],
                    patterns=patterns.split(","), passageID=fields[9] if len(fields) == 10 else None)
            elif fields[0] == "C":
                _, gid, key, markup, translation, prompt, answer, wrong1, wrong2, note = fields
                assert (gid, key) not in contexts, f"duplicate context: {gid}/{key}"
                contexts[(gid, key)] = dict(markup=markup, translation=translation, prompt=prompt,
                    choices=[answer, wrong1, wrong2], answer=answer, note=note)
            elif fields[0] == "B":
                _, gid, source, locator = fields
                assert source and locator
                entry = dict(sourceID=source, locator=locator, status="reference")
                assert entry not in bibliography.setdefault(gid, [])
                bibliography[gid].append(entry)
            else: raise ValueError("expected H, G, C or B record")
        except (ValueError, AssertionError) as error:
            raise ValueError(f"{path}:{line_number}: {error}") from error
    assert all(gid in groups for gid, _ in contexts), "orphan context"
    assert bibliography.keys() <= groups.keys(), "orphan grammar reference"
    known_sources = {r["id"] for r in pack.get("references", [])}
    assert all(c["sourceID"] in known_sources for refs in bibliography.values() for c in refs), "Unknown grammar reference source"
    batch = {key: [] for key in ["items", "sentences", "exercises", "lessons"]}
    coverage = {}
    for gid, group in groups.items():
        examples = [(key, value) for (target, key), value in contexts.items() if target == gid]
        assert len(examples) >= 6, gid
        assert len({v["markup"] for _, v in examples}) == len(examples), gid
        citations = [dict(sourceID="openjlpt", locator=f"grammar/{level.lower()}: " + ", ".join(group["patterns"]), status="reference"),
            dict(sourceID="projectopen", locator=f"原创中文规则、例句及题目 {gid}；未独立语言审校", status="original")]
        citations.extend(bibliography.get(gid, []))
        sids, eids = [], []
        for key, context in examples:
            sid, eid = "s" + gid + key, "e" + gid + key
            segments, position = [], 0
            for match in RUBY.finditer(context["markup"]):
                if match.start() > position:
                    segments.append(dict(text=context["markup"][position:match.start()], reading=None, itemID=None))
                text, reading, lemma = match.groups()
                word = resolve_word(words, text, reading, lemma)
                segments.append(dict(text=text, reading=reading, itemID=word["id"] if word else None))
                position = match.end()
            if position < len(context["markup"]):
                segments.append(dict(text=context["markup"][position:], reading=None, itemID=None))
            assert all(not KANJI.search(s["text"]) or s["reading"] for s in segments), (gid, key, "missing ruby")
            text = "".join(s["text"] for s in segments)
            assert "[" not in text and "]" not in text, (gid, key, "malformed ruby")
            batch["sentences"].append(dict(id=sid, segments=segments, translation=context["translation"],
                explanation=context["note"], speechText=None, citations=citations))
            choices = context["choices"].copy()
            assert len(set(choices)) == 3 and all(choices), (gid, key)
            rotation = int(hashlib.sha256(eid.encode()).hexdigest(), 16) % 3
            choices = choices[rotation:] + choices[:rotation]
            batch["exercises"].append(dict(id=eid, targetID=gid, sentenceID=sid, prompt=context["prompt"],
                choices=choices, answerIndex=choices.index(context["answer"]), explanation=context["note"],
                hint=group["rule"], transfer=key != "a", skill="grammar", ability="structure",
                evidence=text, citations=citations))
            sids.append(sid); eids.append(eid)
        batch["items"].append(dict(id=gid, kind="grammar", level=level, text=group["title"],
            reading=group["reading"], romaji=group["romaji"], meaning=group["meaning"], explanation=group["rule"],
            sourceIDs=list(dict.fromkeys(c["sourceID"] for c in citations)), status="trial", prerequisiteIDs=group["required"],
            citations=citations, exampleSentenceIDs=sids, tags=["structure", level.lower() + "-completion"], order=1000 + len(batch["items"])))
        batch["lessons"].append(dict(id="l" + gid, title=group["title"], subtitle=group["meaning"], level=level,
            itemIDs=[gid], sentenceIDs=sids, exerciseIDs=eids, readingID=group["passageID"],
            prerequisiteIDs=[], objectives=[group["rule"]]))
        for pattern in group["patterns"]:
            coverage.setdefault(pattern, []).append(gid)
    return batch, coverage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manuscript", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    batch, _ = compile_manuscript(args.manuscript, make_pack())
    output = json.dumps(batch, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        assert args.output.read_text() == output, "Grammar batch differs from its manuscript"
    else: args.output.write_text(output)
    print(json.dumps({key: len(records) for key, records in batch.items()}))


if __name__ == "__main__": main()
