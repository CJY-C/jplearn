"""Conservative lexical linking shared by the manuscript compilers."""
import unicodedata


def kana(text):
    text = unicodedata.normalize("NFKC", text)
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def resolve_word(words, text, reading, lemma=None):
    if lemma in ("-", "?"):
        return None
    word = words.get(lemma or text)
    # Inflected stems use an explicitly authored dictionary form. For a whole
    # word, spelling alone cannot distinguish 空/そら from 空/から or 方/ほう.
    if word and text == word["text"] and reading and word.get("reading"):
        accepted = [word["reading"]] + word.get("acceptedReadings", [])
        if kana(reading) not in {kana(value) for value in accepted}:
            return None
    return word
