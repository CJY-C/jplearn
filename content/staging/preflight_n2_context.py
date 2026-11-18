#!/usr/bin/env python3
"""Read-only candidate review before registering the N2 context chapter.

Compile every existing manuscript with the proposed word index. Write the full
link differences only to the requested build artifact; this does not approve
those links or change the runtime pack.
"""
import argparse
import json
from pathlib import Path
import sys

from check_n2_context import ROOT, WORD_FILES
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack
from check_n3_similarity import word_index
from compile_course import COMPILERS, entries
from compile_words import compile_manuscript as compile_words
from compile_grammar import RUBY
from word_links import resolve_word, word_lookup


def check():
    baseline = make_pack()
    index = word_index(baseline, [ROOT / "content/staging" / name for name in WORD_FILES])
    for _ in range(2):
        for name in WORD_FILES:
            batch = compile_words(ROOT / "content/staging" / name, index)
            ids = {w["id"] for w in batch["items"]}
            index["items"] = [w for w in index["items"] if w["id"] not in ids] + batch["items"]
    previous = {s["id"]: s for s in baseline["sentences"]}
    candidates, checked, failures, raw_candidates = [], 0, [], []
    old_lookup, proposed_lookup = word_lookup(baseline["items"]), word_lookup(index["items"])
    for record in entries():
        path = ROOT / "content/authoring" / record["source"]
        # Review every occurrence, even when the first ambiguity prevents the
        # complete manuscript from compiling. Do not silently choose its old
        # meaning: an earlier mistaken association may need a real correction.
        for number, line in enumerate(path.read_text().splitlines(), 1):
            fields = line.split("\t")
            columns = {"C": (3, 4), "E": (3, 4), "S": (4, 5), "X": (2, 3)}
            if fields[0] not in columns:
                continue
            column, translation = columns[fields[0]]
            for surface, reading, lemma in RUBY.findall(fields[column]):
                before = resolve_word(old_lookup, surface, reading, lemma)
                ambiguous = False
                try:
                    after = resolve_word(proposed_lookup, surface, reading, lemma)
                except ValueError:
                    after, ambiguous = None, True
                old_id, new_id = before["id"] if before else None, after["id"] if after else None
                if ambiguous or old_id != new_id:
                    choices = proposed_lookup.get(lemma or surface, []) if ambiguous else ([after] if after else [])
                    raw_candidates.append(dict(source=record["source"], line=number, key=fields[1:3],
                        text=RUBY.sub(lambda m: m[1], fields[column]), translation=fields[translation],
                        surface=surface, reading=reading, lemma=lemma,
                        before=old_id, after=new_id, ambiguous=ambiguous,
                        choices=[dict(id=w["id"], meaning=w["meaning"], reading=w["reading"]) for w in choices]))
        try:
            result = COMPILERS[record["kind"]](path, index)
        except (ValueError, AssertionError) as error:
            failures.append(dict(source=record["source"], error=str(error)))
            continue
        batch = result[0] if record["kind"] == "grammar" else result
        for sentence in batch["sentences"]:
            checked += 1
            old = previous[sentence["id"]]
            # Any non-link mutation needs separate review; do not mask changes
            # to text, ruby, Chinese, questions or source citations as linking.
            stripped = lambda s: dict(s, segments=[dict(v, itemID=None) for v in s["segments"]])
            assert stripped(old) == stripped(sentence), (sentence["id"], "non-link change")
            links = [dict(surface=a["text"], reading=a["reading"], before=a["itemID"], after=b["itemID"])
                     for a, b in zip(old["segments"], sentence["segments"]) if a["itemID"] != b["itemID"]]
            if links:
                candidates.append(dict(source=record["source"], sentenceID=sentence["id"],
                    text="".join(v["text"] for v in sentence["segments"]), translation=sentence["translation"], links=links))
    return dict(status="Candidates only; contextual approval and registration pending",
        checkedSentences=checked, changedSentences=len(candidates),
        changedLinks=sum(len(r["links"]) for r in candidates),
        compilationFailures=failures, rawCandidateOccurrences=len(raw_candidates),
        ambiguousOccurrences=sum(r["ambiguous"] for r in raw_candidates),
        candidates=candidates, rawCandidates=raw_candidates)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = check()
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k not in {"candidates", "rawCandidates", "compilationFailures"}}, ensure_ascii=False))
