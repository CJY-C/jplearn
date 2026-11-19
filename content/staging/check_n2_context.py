#!/usr/bin/env python3
"""Rebuild the N2 context chapter independently of its generated batches.

Checks source compilation, context/ID/prerequisite structure and assessment
isolation. Unresolved forms are candidates; linked word senses still need human
contextual review. Success does not register content or certify language quality.
"""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from build_content import make_pack, validate
from compile_grammar import RUBY, compile_manuscript
from compile_words import compile_manuscript as compile_words
from compile_readings import compile_manuscript as compile_readings
from check_n3_similarity import word_index
from word_links import kana, lexical_words, resolve_word, word_lookup

WORD_FILES = ["n4-context-foundation-words.tsv", "n3-context-foundation-words.tsv",
              "n2-information-and-documents.tsv", "n2-context-prerequisite-words.tsv", "n2-context-reading-words.tsv"]
CHAPTER_FILES = WORD_FILES + ["n2-context-and-mediation.tsv", "n2-context-readings.tsv"]
STAGING = ROOT / "content/staging"


def source_path(name):
    registered = ROOT / "content/authoring" / name
    return registered if registered.exists() else STAGING / name


def base_pack():
    manifest = json.loads((ROOT / "content/manuscripts.json").read_text())
    excluded = set(CHAPTER_FILES)
    later = ROOT / "content/source-checks/n2-basis-chapter.json"
    if later.exists():
        # A later chapter requires the very targets rebuilt by this check.
        # Keep its earlier vocabulary backfill; exclude its dependent N2 units.
        excluded.update(name for name in json.loads(later.read_text())["manuscripts"]
                        if name.startswith("n2-"))
    replacements = {ROOT / "content/batches" / r["batch"]: {}
                    for r in manifest["entries"] if r["source"] in excluded}
    return make_pack(overrides=replacements)

# A prerequisite label alone is not evidence that the new function occurs in
# ordinary practice. These are reviewed surface anchors, not a semantic parser.
ORDINARY_FUNCTION_WITNESSES = {
    "gn2a001": ("rn2001sa", "資料館において開催"),
    "gn2a002": ("rn2002sa", "時代における生活"),
    "gn2a003": ("rn2001sc", "分かりやすさにおいては"),
    "gn2a004": ("rn2003sb", "作業を通して確かめる"),
    "gn2a005": ("rn2003sc", "二か月間を通じて"),
    "gn2a006": ("rn2002sc", "すべて起きたとは限らない"),
    "gn2a007": ("rn2001sc", "案内を改訂したところ"),
    "gn2a008": ("rn2004sc", "誰に向けた発言"),
    "gn2a009": ("rn2003sf", "次の公演に向けて"),
    "gn2a010": ("rn2003sf", "応用するうえでは"),
    "gn2a011": ("rn2004sa", "確認した上で、二つの訳文を比べる"),
    "gn2a012": ("rn2001sb", "地図の上では"),
    "gn2a013": ("rn2004sc", "仕事の上では"),
}


def merge(pack, batch):
    for key, rows in batch.items():
        ids = [r["id"] for r in rows]
        assert len(set(ids)) == len(ids) and not set(ids) & {r["id"] for r in pack[key]}, key
        pack[key].extend(rows)


def check():
    path = source_path("n2-context-and-mediation.tsv")
    pack = base_pack()
    baseline_roots = lexical_words(pack["items"])
    baseline_entries = {w["jmdictEntryID"] for w in baseline_roots if w.get("jmdictEntryID")}
    baseline_forms = {(w["text"], kana(w["reading"])) for w in baseline_roots}
    extra_references = json.loads((STAGING / "n2-context-additional-references.json").read_text())["references"]
    known_sources = {r["id"]: r for r in pack["references"]}
    assert len({r["id"] for r in extra_references}) == len(extra_references)
    for reference in extra_references:
        if reference["id"] in known_sources:
            assert known_sources[reference["id"]] == reference, "Registered reference changed"
        else:
            pack["references"].append(reference)
    original_sentences = list(pack["sentences"])
    word_paths = [source_path(name) for name in WORD_FILES]
    index = word_index(pack, word_paths)
    for _ in range(2):
        for word_path in word_paths:
            word_batch = compile_words(word_path, index)
            ids = {w["id"] for w in word_batch["items"]}
            index["items"] = [w for w in index["items"] if w["id"] not in ids] + word_batch["items"]
    word_batches = []
    for word_path in word_paths:
        word_batch = compile_words(word_path, index)
        record = json.loads((STAGING / (word_path.stem + "-review.json")).read_text())
        assert record["manuscriptSHA256"] == hashlib.sha256(word_path.read_bytes()).hexdigest(), word_path.name
        assert len(word_batch["items"]) == record["targets"] and len(lexical_words(word_batch["items"])) == record["roots"]
        facts = {r["itemID"]: r for r in record["entries"]}
        assert len(facts) == len(word_batch["items"])
        for word in word_batch["items"]:
            fact = facts[word["id"]]
            assert (word["text"], word["reading"], word["meaning"], word["jmdictEntryID"]) == (
                fact["text"], fact["primaryReading"], fact["authoredMeaning"], fact["entryID"]), word["id"]
            assert word.get("lexemeID") == fact["lexemeID"] and word.get("readingOwnerID") == fact["readingOwnerID"], word["id"]
            assert word.get("acceptedReadings", []) == fact["acceptedAlternativeReadings"], word["id"]
            assert word["exampleSentenceIDs"] == fact["exampleSentenceIDs"], word["id"]
            assert [s["acceptedReading"] for s in fact["acceptedReadingSources"]] == [word["reading"]] + word.get("acceptedReadings", []), word["id"]
            for source in fact["acceptedReadingSources"]:
                assert source["entryID"] == fact["entryID"] and source["senseOrdinals"] == fact["senseOrdinals"]
                assert source["readingFacts"] and all(kana(r["reading"]) == kana(source["acceptedReading"]) and
                    not r["nokanji"] and (not r["spellingRestrictions"] or word["text"] in r["spellingRestrictions"]) and
                    not any(flag in info for info in r["information"] for flag in ["obsolete", "out-dated", "search-only"])
                    for r in source["readingFacts"]), word["id"]
                for sense in fact["selectedSenseFacts"]:
                    assert not sense["spellingRestrictions"] or word["text"] in sense["spellingRestrictions"], word["id"]
                    assert not sense["readingRestrictions"] or any(r["reading"] in sense["readingRestrictions"] for r in source["readingFacts"]), word["id"]
        merge(pack, word_batch)
        word_batches.append(word_batch)
    new_roots = lexical_words([w for b in word_batches for w in b["items"]])
    new_entries = [w["jmdictEntryID"] for w in new_roots]
    assert len(set(new_entries)) == len(new_entries), "One dictionary root counted more than once"
    assert not set(new_entries) & baseline_entries, "An existing root must be an extra sense, not a new root"
    assert not {(w["text"], kana(w["reading"])) for w in new_roots} & baseline_forms, "Existing spelling/reading root duplicated"
    batch, coverage = compile_manuscript(path, pack)
    new = {i["id"]: i for i in batch["items"]}
    items = {i["id"]: i for i in pack["items"]}
    assert not new.keys() & items.keys(), "Registered target collision"
    merge(pack, batch)
    validate(pack)
    for item in new.values():
        assert item["level"] == "N2"
        assert set(item["prerequisiteIDs"]) <= items.keys() | new.keys(), item["id"]
    # A draft must not use a self-reference or an internal prerequisite cycle.
    active, visited = set(), set()

    def visit(gid):
        assert gid not in active, (gid, "prerequisite cycle")
        if gid in visited or gid not in new:
            return
        active.add(gid)
        for parent in new[gid]["prerequisiteIDs"]:
            visit(parent)
        active.remove(gid)
        visited.add(gid)

    for gid in new:
        visit(gid)
    sentences = {s["id"]: s for b in word_batches + [batch] for s in b["sentences"]}

    def text(sentence):
        return "".join(s["text"] for s in sentence["segments"])

    values = [text(s) for s in sentences.values()]
    assert len(set(values)) == len(values), "Repeated draft context"
    for gid in new:
        exercises = [e for e in batch["exercises"] if e["targetID"] == gid]
        assert len({text(sentences[e["sentenceID"]]) for e in exercises}) >= 6, gid
    for word_batch in word_batches:
        for word in word_batch["items"]:
            contexts = [sentences[sid] for sid in word["exampleSentenceIDs"]]
            assert len({text(s) for s in contexts}) >= 2, word["id"]
            assert all(any(s["itemID"] == word["id"] for s in c["segments"]) for c in contexts), word["id"]
            levels = {level: index for index, level in enumerate(["N5", "N4", "N3", "N2"])}
            assert all(levels[items[s["itemID"]]["level"]] <= levels[word["level"]]
                       for c in contexts for s in c["segments"] if s["itemID"]), (
                           word["id"], "own context requires a later-level linked target")
    reference = json.loads((ROOT / "content/reference/openjlpt-grammar.json").read_text())
    expected = {r["id"] for r in reference["patterns"] if r["level"] == "N2"}
    assert coverage.keys() <= expected, "Unrecognized N2 pattern"
    heldout = {sid for r in pack["readings"] if r.get("purpose") == "assessment" for sid in r["sentenceIDs"]}
    heldout_text = [text(s) for s in pack["sentences"] if s["id"] in heldout]
    fragments = {t[i:i + 20] for t in heldout_text for i in range(len(t) - 19)}
    for sid, sentence in sentences.items():
        value = text(sentence)
        assert value not in heldout_text
        assert not fragments.intersection(value[i:i + 20] for i in range(len(value) - 19)), sid
    gaps, lookup = defaultdict(list), word_lookup(pack["items"])
    for line in path.read_text().splitlines():
        row = line.split("\t")
        if row[0] != "C":
            continue
        for surface, reading, lemma in RUBY.findall(row[3]):
            if lemma not in {"-", "?"} and not resolve_word(lookup, surface, reading, lemma):
                gaps[lemma or surface].append(row[1] + row[2])
    word_context_gaps = defaultdict(list)
    for word_path in word_paths:
        for line in word_path.read_text().splitlines():
            row = line.split("\t")
            if row[0] != "E":
                continue
            for surface, reading, lemma in RUBY.findall(row[3]):
                if lemma not in {"-", "?"} and not resolve_word(lookup, surface, reading, lemma):
                    word_context_gaps[lemma or surface].append(row[1] + row[2])
    # Explicit references may never silently degrade to an unknown word, even
    # when a narrow sense has different accepted readings from its parent.
    for context_path, tag, column in [(path, "C", 3)] + [(p, "E", 3) for p in word_paths]:
        for line in context_path.read_text().splitlines():
            row = line.split("\t")
            if row[0] != tag:
                continue
            for surface, reading, lemma in RUBY.findall(row[column]):
                if lemma and lemma.startswith("@"):
                    assert resolve_word(lookup, surface, reading, lemma), (row[1:3], lemma, "invalid explicit reading")
    resource = ROOT / "Sources/LearningCore/Resources/foundation.json"
    reading_path = path.with_name("n2-context-readings.tsv")
    reading_batch = compile_readings(reading_path, pack)
    reading_sentences = {s["id"]: s for s in reading_batch["sentences"]}
    passages = {r["id"]: r for r in reading_batch["readings"]}
    reading_gaps, passage_checks = defaultdict(list), []
    practice = [r for r in passages.values() if r["purpose"] == "practice"]
    assessments = [r for r in passages.values() if r["purpose"] == "assessment"]
    assert len(assessments) / len(passages) >= 0.20, "Less than20% heldout readings"
    assert new.keys() <= {gid for r in practice for gid in r["grammarIDs"]}, "Function without ordinary reading"
    assert ORDINARY_FUNCTION_WITNESSES.keys() == new.keys(), "Missing function-use witness"
    for gid, (sid, anchor) in ORDINARY_FUNCTION_WITNESSES.items():
        passage = next(r for r in practice if sid in r["sentenceIDs"])
        assert gid in passage["grammarIDs"] and anchor in text(reading_sentences[sid]), (gid, "ordinary function use changed")
    for lesson in batch["lessons"]:
        reading = passages[lesson["readingID"]]
        assert reading["purpose"] == "practice" and set(lesson["itemIDs"]) <= set(reading["grammarIDs"])
    for reading in passages.values():
        assert reading["level"] == "N2" and len(reading["paragraphs"]) == 2 and len(reading["questions"]) == 2
        assert len(reading["sentenceIDs"]) == 6 and set(reading["grammarIDs"]) <= new.keys() | items.keys()
        length = sum(len(text(reading_sentences[sid])) for sid in reading["sentenceIDs"])
        assert length >= 350, (reading["id"], length)
        passage_checks.append(dict(id=reading["id"], purpose=reading["purpose"], characters=length,
            annotatedOccurrences=len(reading["vocabulary"]), unlinkedOccurrences=sum(w["itemID"] is None for w in reading["vocabulary"])))
    for line in reading_path.read_text().splitlines():
        row = line.split("\t")
        if row[0] != "S":
            continue
        for surface, reading, lemma in RUBY.findall(row[4]):
            word = resolve_word(lookup, surface, reading, lemma)
            if lemma and lemma.startswith("@"):
                assert word, (row[1:3], lemma, "invalid reading reference")
            if lemma not in {"-", "?"} and word is None:
                reading_gaps[lemma or surface].append(row[1] + "s" + row[2])
    held_ids = {sid for r in assessments for sid in r["sentenceIDs"]}
    training = list(sentences.values()) + [s for s in reading_batch["sentences"] if s["id"] not in held_ids]
    # Old assessments stay isolated from every new practice/example as well.
    for s in training:
        value = text(s)
        assert value not in heldout_text and not fragments.intersection(value[i:i + 20] for i in range(len(value) - 19)), s["id"]
    prior_and_practice = [text(s) for s in original_sentences + training]
    practice_fragments = {t[i:i + 20] for t in prior_and_practice for i in range(len(t) - 19)}
    for sid in held_ids:
        value = text(reading_sentences[sid])
        assert value not in prior_and_practice and not practice_fragments.intersection(value[i:i + 20] for i in range(len(value) - 19)), sid
    all_new = list(sentences.values()) + list(reading_sentences.values())
    assert len({s["id"] for s in all_new}) == len(all_new), "Duplicate draft sentence ID"
    assert len({text(s) for s in all_new}) == len(all_new), "Duplicate draft sentence text"
    old_texts = {text(s) for s in original_sentences}
    assert not old_texts.intersection(text(s) for s in all_new), "Registered text reused under a new ID"
    for key, rows in reading_batch.items():
        assert not {r["id"] for r in rows} & {r["id"] for r in pack[key]}, (key, "Registered reading collision")
    complete_pack_validated = not (gaps or word_context_gaps or reading_gaps)
    if complete_pack_validated:
        merge(pack, reading_batch)
        validate(pack)
    registered = path.parent.name == "authoring"
    runtime_sha = hashlib.sha256(resource.read_bytes()).hexdigest()
    baseline_sha = (json.loads((ROOT / "content/source-checks/n2-context-chapter.json").read_text())["baselineRuntimeSHA256"]
                    if registered else runtime_sha)
    return dict(status=("Registered trial source; structure, source facts and isolation checked; independent language review0" if registered else
                       "Unregistered draft; source/structure/isolation checked, contextual word-sense and independent language review pending"),
        manuscript=str(path.relative_to(ROOT)), manuscriptSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),
        baselineRuntimeVersion=pack["version"], baselineRuntimeSHA256=baseline_sha,
        runtimeResourceSHA256=runtime_sha, sourceReconstructionExcludesOwnBatches=True,
        draftGrammarFunctions=len(new), draftOriginalContexts=len(batch["sentences"]), draftExercises=len(batch["exercises"]),
        draftLessons=len(batch["lessons"]), draftReferencePatterns=coverage,
        registeredNewN2Targets=(sum(w["level"] == "N2" for b in word_batches for w in b["items"]) + len(new)) if registered else 0,
        wordRoots=sum(len(lexical_words(b["items"])) for b in word_batches), wordTargets=sum(len(b["items"]) for b in word_batches),
        n2WordRoots=sum(w["level"] == "N2" for b in word_batches for w in lexical_words(b["items"])),
        n4FoundationRoots=sum(w["level"] == "N4" for b in word_batches for w in lexical_words(b["items"])),
        n3FoundationRoots=sum(w["level"] == "N3" for b in word_batches for w in lexical_words(b["items"])),
        wordContexts=sum(len(b["sentences"]) for b in word_batches), wordLessons=sum(len(b["lessons"]) for b in word_batches),
        earlierOwnContextsHaveNoLaterLevelLinkedTargets=True,
        wordManuscripts={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in word_paths},
        readingManuscript=str(reading_path.relative_to(ROOT)), readingManuscriptSHA256=hashlib.sha256(reading_path.read_bytes()).hexdigest(),
        readings=len(passages), practiceReadings=len(practice), assessmentReadings=len(assessments), readingQuestions=sum(len(r["questions"]) for r in passages.values()),
        allDraftFunctionsUsedInOrdinaryReadings=True,
        ordinaryFunctionWitnesses={gid: dict(sentenceID=sid, surface=anchor) for gid, (sid, anchor) in ORDINARY_FUNCTION_WITNESSES.items()},
        completeDraftPackValidated=complete_pack_validated, passageChecks=passage_checks,
        readingRulePrerequisites={rid: r["rulePrerequisites"] for rid, r in passages.items() if r.get("rulePrerequisites")},
        unresolvedReadingForms=len(reading_gaps), readingGaps=dict(sorted(reading_gaps.items())),
        unresolvedWordExampleForms=len(word_context_gaps), wordExampleGaps=dict(sorted(word_context_gaps.items())),
        readingRegistrationReady=registered and complete_pack_validated,
        heldoutFragmentCharacters=20, heldoutLeaks=0, unresolvedForms=len(gaps), gaps=dict(sorted(gaps.items())),
        independentLanguageReviews=0, remaining=([
            "Complete the remaining additionalN2 roots/functions/readings and all six bridges; chapter registration is not fullN2 completion.",
            "Run native iOS integration,SE3,archive and device/voice checks; no new IPA is implied by source registration.",
            "Independent Japanese language review remains0; source and structural checks do not certify language quality."
        ] if registered else ["Finish contextual decisions, register and run full validation.",
            "Preserve2500 additionalN2 roots,140 functions,140 readings,100 lessons,28 assessments and six3-reading bridges."]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-report", action="store_true")
    args = parser.parse_args()
    result = check()
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    report = ROOT / "content/staging/n2-context-and-mediation-review.json"
    if args.update_report:
        report.write_text(encoded)
    else:
        assert report.read_text() == encoded, "Review the changed draft, then --update-report"
    print(json.dumps({k: result[k] for k in ["draftGrammarFunctions", "draftOriginalContexts", "draftExercises",
        "draftLessons", "unresolvedForms", "heldoutLeaks", "registeredNewN2Targets"]}, ensure_ascii=False))
