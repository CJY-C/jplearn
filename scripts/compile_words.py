#!/usr/bin/env python3
"""Compile explicitly authored vocabulary and two real contexts per target.

L: lesson id, title. W: id, spelling, reading, romaji, Chinese sense, POS, lesson,
   two explicitly authored contrasting meanings.
E: word id, stable context key, ruby sentence, Chinese translation.
A: word id, alternative readings, source id, source locator (same sense only).
D: word id, a short sense cue needed to disambiguate an isolated spelling.
N: word id, an authored usage note appended to the explanation.
This compiler never manufactures sentences or translates source material.
"""
import argparse
import hashlib
import json
import re

from build_content import ROOT, make_pack
from compile_readings import markup_sentence


def compile_manuscript(path, pack):
    lessons, words, examples, alternatives, cues, notes = {}, {}, {}, {}, {}, {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line or line.startswith("#"): continue
        try:
            fields = line.split("\t")
            if fields[0] == "L":
                _, lid, title = fields
                assert lid not in lessons
                lessons[lid] = title
            elif fields[0] == "W":
                _, wid, text, reading, romaji, meaning, pos, lid, wrong1, wrong2 = fields
                assert wid not in words
                assert re.fullmatch("[ぁ-ゖー]+", reading)
                words[wid] = dict(id=wid, text=text, reading=reading, romaji=romaji,
                    meaning=meaning, pos=pos, lessonID=lid, distractors=[wrong1, wrong2])
            elif fields[0] == "E":
                _, wid, key, text, translation = fields
                assert (wid, key) not in examples
                examples[(wid, key)] = (text, translation)
            elif fields[0] == "A":
                _, wid, readings, source, locator = fields
                assert wid not in alternatives
                alternatives[wid] = (readings.split(","), source, locator)
            elif fields[0] == "D":
                _, wid, cue = fields
                assert wid not in cues and cue
                cues[wid] = cue
            elif fields[0] == "N":
                _, wid, note = fields
                assert wid not in notes and note
                notes[wid] = note
            else: raise ValueError("expected L, W, E, A, D or N")
        except (ValueError, AssertionError) as error:
            raise ValueError(f"{path}:{number}: {error}") from error
    assert all(wid in words for wid, _ in examples) and (set(alternatives) | set(cues) | set(notes)) <= words.keys()
    lookup = {}
    for word in pack["items"]:
        if word["kind"] == "word" and word["id"] not in words:
            lookup.setdefault(word["text"], word)
    for word in words.values():
        assert word["text"] not in lookup, (word["id"], "duplicate spelling; reuse the existing target")
        if word["id"] in alternatives:
            word["acceptedReadings"] = alternatives[word["id"]][0]
        lookup[word["text"]] = word
        assert word["lessonID"] in lessons
    batch = {key: [] for key in ["items", "sentences", "exercises", "lessons"]}
    for word in words.values():
        wid = word["id"]
        contexts = [(key, value) for (target, key), value in examples.items() if target == wid]
        assert len(contexts) >= 2, wid
        citations = [dict(sourceID="projectopen", locator=f"原创词义整理与语境 {wid}；未独立语言审校", status="original")]
        sids, texts = [], set()
        for key, (markup, translation) in contexts:
            sid = "s" + wid + key
            segments, _ = markup_sentence(markup, lookup)
            text = "".join(s["text"] for s in segments)
            assert text not in texts and any(s["itemID"] == wid for s in segments), (wid, key)
            texts.add(text); sids.append(sid)
            batch["sentences"].append(dict(id=sid, segments=segments, translation=translation,
                explanation="注意本词在这个具体场景中的意思及搭配。", speechText=None, citations=citations))
        batch["items"].append(dict(id=wid, kind="word", level="N5", text=word["text"], reading=word["reading"],
            romaji=word["romaji"], meaning=word["meaning"], explanation=f'本单元义项：{word["meaning"]}。通过两个不同语境辨认；其他义项须结合上下文。',
            sourceIDs=["projectopen"], status="trial", partOfSpeech=word["pos"], sense=word["meaning"],
            register="一般", tags=["reading-foundation"], prerequisiteIDs=[], citations=citations,
            exampleSentenceIDs=sids, order=2000 + len(batch["items"])))
        if wid in alternatives:
            readings, source, locator = alternatives[wid]
            assert len(set(readings)) == len(readings)
            assert all(re.fullmatch("[ぁ-ゖー]+", x) and x != word["reading"] for x in readings)
            batch["items"][-1]["acceptedReadings"] = readings
            batch["items"][-1]["sourceIDs"].append(source)
            batch["items"][-1]["citations"].append(dict(sourceID=source, locator=locator, status="reference"))
        if wid in cues: batch["items"][-1]["readingCue"] = cues[wid]
        if wid in notes: batch["items"][-1]["explanation"] += "\n" + notes[wid]
        answer = word["meaning"]
        choices = [answer] + word["distractors"]
        assert len(set(choices)) == 3 and all(choices), wid
        eid = "e" + wid + "a"
        rotation = int(hashlib.sha256(eid.encode()).hexdigest(), 16) % 3
        choices = choices[rotation:] + choices[:rotation]
        batch["exercises"].append(dict(id=eid, targetID=wid, sentenceID=sids[1], skill="meaning",
            prompt=f'句中「{word["text"]}」表示什么？', choices=choices, answerIndex=choices.index(answer),
            explanation=f'本句中对应的义项是「{answer}」；结合句子所描述的人物、对象或动作理解。',
            hint=word["reading"], transfer=True, ability="contextMeaning", evidence=word["text"], citations=citations))
    for lid, title in lessons.items():
        ids = [w["id"] for w in words.values() if w["lessonID"] == lid]
        assert ids, lid
        batch["lessons"].append(dict(id=lid, title=title, subtitle="读音、词义和两个实际语境", level="N5", itemIDs=ids,
            sentenceIDs=["s" + wid + key for wid, key in examples if wid in ids],
            exerciseIDs=["e" + wid + "a" for wid in ids], readingID=None, prerequisiteIDs=[],
            objectives=["辨认本组词在句段中的读音与具体含义。"] ))
    return batch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manuscript")
    parser.add_argument("output")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    batch = compile_manuscript(ROOT / args.manuscript, make_pack())
    output = json.dumps(batch, ensure_ascii=False, indent=2) + "\n"
    if args.check: assert (ROOT / args.output).read_text() == output, "Vocabulary batch differs from manuscript"
    else: (ROOT / args.output).write_text(output)
    print(json.dumps({key: len(value) for key, value in batch.items()}))


if __name__ == "__main__": main()
