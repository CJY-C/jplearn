#!/usr/bin/env python3
"""Compile explicitly authored reading manuscripts without runtime downloads.

R: id, title, genre, level, purpose, required grammar ids.
S: reading id, stable sentence key, paragraph key, ruby text, Chinese translation.
Q: reading id, key, prompt, answer, two distractors, evidence sentence keys,
   ability, explanation.
X: standalone sentence id, ruby text, translation, explanation (example repairs).

Every [surface|reading|optional lemma] is an explicit lexical occurrence. A
lemma of "-" marks furigana for grammar text (for example comparison 方), which
is assessed through prerequisites rather than the content-word denominator. A
lemma of "?" forces an unknown proper name rather than a homonymous word. An
unbundled lemma is kept with a null itemID and counts as unknown in readiness.
Particles and conjugation endings remain outside brackets. No NLP is needed.
"""
import argparse
from collections import defaultdict
import hashlib
import json
import re

from build_content import ROOT, make_pack
from compile_grammar import RUBY, KANJI
from word_links import resolve_word


def markup_sentence(markup, words):
    segments, occurrences, position = [], [], 0
    for match in RUBY.finditer(markup):
        if match.start() > position:
            segments.append(dict(text=markup[position:match.start()], reading=None, itemID=None))
        text, reading, lemma = match.groups()
        word = resolve_word(words, text, reading, lemma)
        segments.append(dict(text=text, reading=reading, itemID=word["id"] if word else None))
        if lemma != "-":
            occurrences.append(dict(text=word["text"] if word else text if lemma == "?" else lemma or text,
                itemID=word["id"] if word else None))
        position = match.end()
    if position < len(markup):
        segments.append(dict(text=markup[position:], reading=None, itemID=None))
    text = "".join(s["text"] for s in segments)
    assert text and "[" not in text and "]" not in text, markup
    assert all(not KANJI.search(s["text"]) or s["reading"] for s in segments), markup
    return segments, occurrences


def compile_manuscript(path, pack):
    words = {}
    for word in pack["items"]:
        if word["kind"] == "word": words.setdefault(word["text"], word)
    readings, sentences, questions, standalone = {}, {}, {}, {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line or line.startswith("#"): continue
        try:
            fields = line.split("\t")
            if fields[0] == "R":
                _, rid, title, genre, level, purpose, grammar = fields
                assert rid not in readings
                assert purpose in ["practice", "assessment", "extensive"]
                readings[rid] = dict(id=rid, title=title, genre=genre, level=level,
                    purpose=purpose, grammarIDs=grammar.split(","))
            elif fields[0] == "S":
                _, rid, key, paragraph, text, translation = fields
                assert (rid, key) not in sentences
                sentences[(rid, key)] = (paragraph, text, translation)
            elif fields[0] == "Q":
                _, rid, key, prompt, answer, wrong1, wrong2, evidence, ability, note = fields
                assert (rid, key) not in questions
                questions[(rid, key)] = dict(prompt=prompt, choices=[answer, wrong1, wrong2],
                    evidence=evidence.split(","), ability=ability, explanation=note)
            elif fields[0] == "X":
                _, sid, text, translation, note = fields
                assert sid not in standalone
                standalone[sid] = (text, translation, note)
            else: raise ValueError("expected R, S, Q or X")
        except (ValueError, AssertionError) as error:
            raise ValueError(f"{path}:{number}: {error}") from error
    assert all(rid in readings for rid, _ in sentences), "orphan sentence"
    assert all(rid in readings for rid, _ in questions), "orphan question"
    batch = dict(sentences=[], readings=[])
    for sid, (text, translation, note) in standalone.items():
        segments, _ = markup_sentence(text, words)
        batch["sentences"].append(dict(id=sid, segments=segments, translation=translation,
            explanation=note, speechText=None, citations=[dict(sourceID="projectopen",
                locator=f"原创独立例句 {sid}；未独立语言审校", status="original")]))
    for rid, reading in readings.items():
        citations = [dict(sourceID="projectopen", locator=f"原创分级短文与题目 {rid}；未独立语言审校", status="original")]
        sids, vocabulary, paragraphs, paragraph_ids = [], [], [], []
        texts = []
        for (target, key), (paragraph, markup, translation) in sentences.items():
            if target != rid: continue
            sid = rid + "s" + key
            segments, occurrences = markup_sentence(markup, words)
            assert occurrences, (rid, key, "empty lexical annotation")
            text = "".join(s["text"] for s in segments)
            assert text not in texts, (rid, "duplicate sentence")
            texts.append(text)
            batch["sentences"].append(dict(id=sid, segments=segments, translation=translation,
                explanation="结合篇章中的人物、时间、地点与前后关系理解。", speechText=None, citations=citations))
            if not paragraph_ids or paragraph_ids[-1] != paragraph:
                assert paragraph not in paragraph_ids, (rid, "non-contiguous paragraph")
                paragraph_ids.append(paragraph); paragraphs.append(dict(sentenceIDs=[], vocabulary=[]))
            paragraphs[-1]["sentenceIDs"].append(sid)
            paragraphs[-1]["vocabulary"].extend(occurrences)
            sids.append(sid); vocabulary.extend(occurrences)
        assert len(sids) >= 3, rid
        qs = []
        for (target, key), question in questions.items():
            if target != rid: continue
            qid = rid + "q" + key
            choices = question["choices"].copy(); answer = choices[0]
            assert len(set(choices)) == 3 and all(choices)
            rotation = int(hashlib.sha256(qid.encode()).hexdigest(), 16) % 3
            choices = choices[rotation:] + choices[:rotation]
            evidence = [rid + "s" + key for key in question["evidence"]]
            assert evidence and set(evidence) <= set(sids), (rid, evidence)
            qs.append(dict(id=qid, prompt=question["prompt"], choices=choices,
                answerIndex=choices.index(answer), explanation=question["explanation"],
                evidenceSentenceIDs=evidence, ability=question["ability"]))
        assert 1 <= len(qs) <= 4, rid
        first = qs[0]
        batch["readings"].append(dict(**reading, sentenceIDs=sids, question=first["prompt"],
            choices=first["choices"], answerIndex=first["answerIndex"], explanation=first["explanation"],
            vocabulary=vocabulary, paragraphs=paragraphs, questions=qs, citations=citations))
    return batch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manuscript", type=str)
    parser.add_argument("output", type=str)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    batch = compile_manuscript(ROOT / args.manuscript, make_pack())
    output = json.dumps(batch, ensure_ascii=False, indent=2) + "\n"
    target = ROOT / args.output
    if args.check: assert target.read_text() == output, "Reading batch differs from manuscript"
    else: target.write_text(output)
    print(json.dumps({key: len(value) for key, value in batch.items()}))


if __name__ == "__main__": main()
