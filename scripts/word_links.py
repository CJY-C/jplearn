"""Conservative lexical linking shared by the manuscript compilers."""
import unicodedata


def lexical_words(items):
    """Extra senses retain their own study IDs without counting as new words."""
    return [w for w in items if w["kind"] == "word" and not w.get("lexemeID")]


def validate_lexemes(items):
    words = {w["id"]: w for w in items if w["kind"] == "word"}
    for word in words.values():
        for field in ("lexemeID", "readingOwnerID"):
            if word.get(field) is not None:
                assert isinstance(word[field], str) and word[field], (word["id"], "empty word association")
        if owner_id := word.get("lexemeID"):
            owner = words.get(owner_id)
            assert owner and not owner.get("lexemeID") and owner_id != word["id"], (word["id"], "invalid lexeme owner")
            owner_readings = {kana(x) for x in [owner["reading"]] + owner.get("acceptedReadings", [])}
            own_readings = {kana(x) for x in [word["reading"]] + word.get("acceptedReadings", [])}
            assert word["text"] == owner["text"] and own_readings <= owner_readings, (word["id"], "sense must share its word form")
            assert word["meaning"] != owner["meaning"], (word["id"], "duplicate sense")
        if reading_owner := word.get("readingOwnerID"):
            owner = words.get(reading_owner)
            assert owner and word.get("lexemeID") == reading_owner, (word["id"], "invalid shared reading")
            first = {kana(x) for x in [word["reading"]] + word.get("acceptedReadings", [])}
            second = {kana(x) for x in [owner["reading"]] + owner.get("acceptedReadings", [])}
            assert first == second, (word["id"], "different reading constraints cannot share a review")
    by_text = {}
    for word in words.values():
        for previous in by_text.setdefault(word["text"], []):
            first = {kana(x) for x in [word["reading"]] + word.get("acceptedReadings", [])}
            second = {kana(x) for x in [previous["reading"]] + previous.get("acceptedReadings", [])}
            if first & second:
                assert (word.get("lexemeID") or word["id"]) == (previous.get("lexemeID") or previous["id"]), (word["text"], "duplicate spelling; reuse the existing target or declare a sense group")
                assert word["meaning"] != previous["meaning"], (word["id"], "duplicate sense")
        by_text[word["text"]].append(word)


def word_lookup(items):
    """An ambiguous spelling needs an explicit @itemID, never array order."""
    by_text, lookup = {}, {}
    for word in items:
        if word["kind"] != "word": continue
        by_text.setdefault(word["text"], []).append(word)
        lookup["@" + word["id"]] = word
    for text, choices in by_text.items():
        lookup[text] = choices[0] if len(choices) == 1 else choices
    return lookup


def kana(text):
    text = unicodedata.normalize("NFKC", text)
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def stem_reading_matches(reading, dictionary_reading, internal=False):
    """Allow partial ruby and ordinary inflection, not a different homograph.

    A stem such as 開/ひら cannot inherit 開く/あく just because an author
    supplied its spelling as the lemma. Ruby may also include okurigana, as
    in 帰った/かえった, so the dictionary ending is not required verbatim.
    """
    reading, base = kana(reading), kana(dictionary_reading)
    if base.startswith(reading): return True
    if len(base) > 1 and reading.startswith(base[:-1]): return True
    if base.endswith("する") and reading.startswith(tuple(base[:-2] + suffix for suffix in ("し", "せ", "さ"))): return True
    if base == "くる" and reading.startswith(("き", "こ")): return True
    if base == "いい" and reading.startswith("よ"): return True
    # Ruby can cover an internal kanji after an unannotated kana prefix,
    # e.g. すれ[違|ちが]う or お[嬢|じょう]さん.
    if internal and reading in base: return True
    if internal and len(reading) > 1 and reading[:-1] in base[:-1]: return True
    return False


def resolve_word(words, text, reading, lemma=None):
    if lemma in ("-", "?"):
        return None
    word = words.get(lemma or text)
    if lemma and lemma.startswith("@") and word is None:
        raise ValueError(f"Unknown explicit word reference: {lemma}")
    if isinstance(word, list):
        raise ValueError(f"Ambiguous word reference: {lemma or text}; use @itemID or ?")
    # Inflected stems use an explicitly authored dictionary form. For a whole
    # word, spelling alone cannot distinguish 空/そら from 空/から or 方/ほう.
    if word and reading and word.get("reading"):
        accepted = [word["reading"]] + word.get("acceptedReadings", [])
        stem_text, stem_reading = text, kana(reading)
        # An authored collocation may include a focus particle: 電話にも出ない
        # still uses 電話に出る. Remove it only when the remaining written stem
        # matches that collocation, rather than accepting an arbitrary reading.
        if "に" in word["text"]:
            for focus in ("にも", "には"):
                plain = stem_text.replace(focus, "に")
                if plain != stem_text and (word["text"].startswith(plain) or plain.startswith(word["text"][:-1])):
                    stem_text = plain
                    stem_reading = stem_reading.replace(focus, "に")
        # Honorific prefixes may be inside the same authored ruby span. Only
        # remove a matching written and spoken prefix, then check the actual
        # lexical pronunciation below (お名前 is still 名前/なまえ).
        for prefix in ("お", "ご"):
            plain = stem_text.removeprefix(prefix)
            if plain != stem_text and stem_reading.startswith(prefix) and (
                word["text"].startswith(plain) or plain.startswith(word["text"][:-1])
            ):
                stem_text = plain
                stem_reading = stem_reading[1:]
        written_stem = stem_text
        while written_stem and "\u3040" <= written_stem[-1] <= "\u30ff":
            written_stem = written_stem[:-1]
        internal = bool(written_stem and word["text"].find(written_stem) > 0)
        valid = (kana(reading) in {kana(value) for value in accepted}) if text == word["text"] else (
            any(stem_reading_matches(stem_reading, value, internal) for value in accepted))
        if not valid:
            return None
    return word
