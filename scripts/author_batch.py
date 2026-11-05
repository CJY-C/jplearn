"""One-time authoring helpers. The resulting JSON records are the editable source of truth."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Author:
    def __init__(self):
        self.legacy = {key: json.loads((ROOT / f"content/legacy/{key}.json").read_text())
                       for key in ["items", "sentences", "exercises", "readings", "lessons"]}
        self.batch = {key: [] for key in ["items", "sentences", "exercises", "readings", "lessons", "introModules"]}
        self.words = {x["text"]: x for x in self.legacy["items"] if x["kind"] == "word"}
        self.aliases = {}
        for sentence in self.legacy["sentences"]:
            for segment in sentence["segments"]:
                if segment["itemID"]:
                    self.aliases[(segment["text"], segment["reading"])] = segment["itemID"]

    def citation(self, chapter, status="reference", source="taekim"):
        return dict(sourceID=source, locator=chapter, status=status)

    def sentence(self, identifier, markup, translation, chapter, explanation="结合人物、动作及上下文理解。"):
        segments, position = [], 0
        for match in re.finditer(r"\[([^|\]]+)\|([^|\]]+)(?:\|([^\]]+))?\]", markup):
            if match.start() > position: segments.append(dict(text=markup[position:match.start()], reading=None, itemID=None))
            text, reading, lemma = match.groups()
            if lemma:
                assert lemma in self.words, (identifier, lemma)
                item_id = self.words[lemma]["id"]
            else: item_id = self.words.get(text, {}).get("id") or self.aliases.get((text, reading))
            segments.append(dict(text=text, reading=reading if re.search(r"[一-龯]", text) else None, itemID=item_id))
            position = match.end()
        if position < len(markup): segments.append(dict(text=markup[position:], reading=None, itemID=None))
        self.batch["sentences"].append(dict(id=identifier, segments=segments, translation=translation,
            explanation=explanation, speechText=None, citations=[self.citation(chapter), self.citation("新增例句与中文翻译，未独立语言审校", "original", "project")]))
        return identifier

    def question(self, identifier, prompt, choices, answer, explanation, evidence, ability="information"):
        return dict(id=identifier, prompt=prompt, choices=choices, answerIndex=answer,
                    explanation=explanation, evidenceSentenceIDs=evidence, ability=ability)

    def save(self, filename="001-foundation.json"):
        path = ROOT / "content/batches" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.batch, ensure_ascii=False, indent=2) + "\n")
