"""Generate the SC4 fixtures and oracle files of score-backend-midi.

    uv run --no-project --with music21==10.5.2 --with mido==1.3.3 \\
        python -I tests/fixtures/generate-sc4.py [--renumber]
    uv run --no-project --with mido==1.3.3 python -I tests/fixtures/generate-sc4.py --dump

This script is a second implementation of the rules in src/*.lisp, in Python,
written from the file headers and independent of the Lisp code. Where the
rules are about music (which notes sound when, after repeats, jumps and ties),
music21 10.5.2 is the oracle: every fixture score is also built in music21,
expanded with expandRepeats and stripTies, and the script stops when music21's
notes, bar order or tempi differ from its own. mido 1.3.3 writes every .mid
file, so the bytes are mido's encoding of the events the rules call for.

Outputs (tests/fixtures/PROVENANCE.md has the table):
  sc4-export-*.mid       SCORE-TO-SMF of each fixture score, default options
  sc4-variant-*.mid      the same for the option rows of sc4-variants.sexp
  sc4-export-facts.sexp  per fixture: played bars, meta events, per-voice notes,
                         lyrics and spellings, losses, and the measure map the
                         import must rebuild
  sc4-quantize.sexp      QUANTIZE-ONSETS rows (brute force over every grid)
  sc4-perf-*.mid         humanised renderings of ten melodies (below)
  sc4-performances.sexp  their notation (ground truth) and the import's result
  sc4-*.mid (import)     hand-designed import files; facts in sc4-import-facts.sexp
  sc41-*.mid             0.1.1: the performance of issue #4 and a late last note
                         (issue #3); facts and the rules' import in sc41-facts.sexp
--renumber rewrites the sc4-*.sexp fixture scores with ids in document order
(as generate-sc0.py does in score-protocol); without it the script checks them.
--dump reads SMFs concatenated on stdin and prints, for each, what mido reads:
(format division ((track-name ((tick kind channel key velocity)...))...)).
"""

import io
import math
import os
import random
import re
import sys
from fractions import Fraction as F

HERE = os.path.dirname(os.path.abspath(__file__))

# --- s-expressions (as in score-protocol's generate-sc0.py) -----------------


class Node:
    def __init__(self, kind, value, start, end, tail=None):
        self.kind, self.value, self.start, self.end, self.tail = kind, value, start, end, tail


TOKEN = re.compile(r'\s+|;[^\n]*|\(|\)|"(?:[^"\\]|\\.)*"|[^\s()";]+')
NUMBER = re.compile(r'^[+-]?\d+(/\d+)?$|^[+-]?\d*\.\d+$')


def parse(text):
    pos, stack, starts = 0, [[]], []
    while pos < len(text):
        m = TOKEN.match(text, pos)
        tok, start, pos = m.group(0), m.start(), m.end()
        if tok[0].isspace() or tok[0] == ";":
            continue
        if tok == "(":
            stack.append([])
            starts.append(start)
        elif tok == ")":
            items_ = stack.pop()
            tail = None
            if len(items_) >= 3 and items_[-2].kind == "sym" and items_[-2].value == ".":
                tail, items_ = items_[-1], items_[:-2]
            stack[-1].append(Node("list", items_, starts.pop(), pos, tail))
        elif tok[0] == '"':
            stack[-1].append(Node("str", re.sub(r'\\(.)', r'\1', tok[1:-1]), start, pos))
        elif tok[0] == ":":
            stack[-1].append(Node("kw", tok[1:].lower(), start, pos))
        elif NUMBER.match(tok):
            stack[-1].append(Node("num", float(tok) if "." in tok else F(tok), start, pos))
        else:
            stack[-1].append(Node("sym", tok.lower(), start, pos))
    (top,) = stack[0]
    return top


def plist(node):
    items_ = node.value
    return items_[0].value, {items_[i].value: items_[i + 1] for i in range(1, len(items_), 2)}


def items(node):
    return [] if node is None or node.kind == "sym" else node.value


def val(keys, name, default=None):
    node = keys.get(name)
    if node is None:
        return default
    if node.kind == "sym":
        return True if node.value == "t" else None
    return node.value


PREFIX = {"measure": "m", "part": "p", "staff": "st", "voice": "v", "rest": "e",
          "note": "e", "chord": "e", "chord-note": "n", "lyric": "ly",
          "chord-symbol": "h", "spanner": "sp", "dynamic": "dy", "fermata": "fe",
          "breath-mark": "br", "articulation": "ar", "tie": "ti", "tempo-mark": "tm",
          "rehearsal": "rh", "jump": "jm", "ending": "en"}


def base36(n):
    digits = ""
    while n:
        n, d = divmod(n, 36)
        digits = "0123456789abcdefghijklmnopqrstuvwxyz"[d] + digits
    return digits


def is_element(node):
    return (node is not None and node.kind == "list" and node.value
            and node.value[0].kind == "kw" and node.value[0].value in PREFIX)


def element_children(value):
    if is_element(value):
        yield value
    elif value is not None and value.kind == "list":
        for item in value.value:
            if is_element(item):
                yield item
            elif item.kind == "list":
                for inner in item.value:
                    if is_element(inner):
                        yield inner


def walk(form):
    yield form
    _, keys = plist(form)
    for value in keys.values():
        for child in element_children(value):
            yield from walk(child)


def document_order(score):
    _, s = plist(score)
    for value in s.values():
        for child in element_children(value):
            yield from walk(child)


def renumbered(text):
    """TEXT with ids minted in document order and references followed."""
    score = parse(text)
    edits, mapping, refs = [], {}, []
    elements = list(document_order(score))
    for serial, element in enumerate(elements, 1):
        kind, keys = plist(element)
        new = f"{PREFIX[kind]}-{base36(serial)}"
        old = keys.get("id")
        if old is not None:
            mapping[old.value] = new
            edits.append((old.start, old.end, f'"{new}"'))
        else:
            head = element.value[0]
            edits.append((head.end, head.end, f' :id "{new}"'))
        for ref in ("start", "end"):
            if ref in keys and kind in ("spanner", "tie"):
                refs.append(keys[ref])
    for ref in refs:
        edits.append((ref.start, ref.end, f'"{mapping[ref.value]}"'))
    _, s = plist(score)
    counter = s["id-counter"]
    edits.append((counter.start, counter.end, str(len(elements))))
    for start, end, new in sorted(edits, reverse=True):
        text = text[:start] + new + text[end:]
    return text


def lisp(value):
    if value is True:
        return "t"
    if value is None or value is False:
        return "nil"
    if isinstance(value, Kw):
        return ":" + value.name
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, F):
        return str(value.numerator) if value.denominator == 1 else f"{value.numerator}/{value.denominator}"
    if isinstance(value, float):
        return repr(value) + "d0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, Cons):
        return f"({lisp(value.car)} . {lisp(value.cdr)})"
    if isinstance(value, (list, tuple)):
        return "(" + " ".join(lisp(v) for v in value) + ")"
    raise TypeError(value)


class Kw:
    def __init__(self, name):
        self.name = name


class Cons:
    def __init__(self, car, cdr):
        self.car, self.cdr = car, cdr


def write_form(name, header, rows):
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as out:
        out.write(f";;;; {header}\n;;;; Generated by generate-sc4.py. Do not edit.\n(\n")
        for row in rows:
            out.write(" " + lisp(row) + "\n")
        out.write(")\n")


# --- music-theory facts, re-derived ---------------------------------------

LETTERS = "CDEFGAB"
LETTER_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
LETTER_FIFTHS = {"F": -1, "C": 0, "G": 1, "D": 2, "A": 3, "E": 4, "B": 5}
ALTERS = {"": 0, "#": 1, "##": 2, "b": -1, "bb": -2}


def split_pitch(name):
    m = re.match(r"^([A-G])(##|#|bb|b|)(-?\d+)$", name)
    return m.group(1), ALTERS[m.group(2)], int(m.group(3))


def midi_of(name):
    letter, alter, octave = split_pitch(name)
    return 12 * (octave + 1) + LETTER_PC[letter] + alter


def fifths_of(pc_name):
    """Line-of-fifths position of a pitch-class name ("F#", "Bb")."""
    letter, alter = pc_name[0], ALTERS[pc_name[1:]]
    return LETTER_FIFTHS[letter] + 7 * alter


def pc_name_of_fifths(f):
    for letter, base in LETTER_FIFTHS.items():
        if (f - base) % 7 == 0:
            alter = (f - base) // 7
            return letter + {0: "", 1: "#", 2: "##", -1: "b", -2: "bb"}[alter]


def parse_key(text):
    tonic, mode = text.split(" ")
    return tonic, mode


def key_sharps(text):
    tonic, mode = parse_key(text)
    return fifths_of(tonic) + (0 if mode == "major" else -3)


def key_of_sharps(sharps, minor):
    if minor:
        return pc_name_of_fifths(sharps + 3) + " minor"
    return pc_name_of_fifths(sharps) + " major"


def key_positions(text):
    """MT4's K: the key's spelled notes on the line of fifths (harmonic minor)."""
    tonic, mode = parse_key(text)
    t = fifths_of(tonic)
    return {t + d for d in ((-1, 0, 1, 2, 3, 4, 5) if mode == "major" else (-4, -3, -1, 0, 1, 2, 5))}


def pitch_in_k(name, key):
    letter, alter, _ = split_pitch(name)
    return LETTER_FIFTHS[letter] + 7 * alter in key_positions(key)


def parse_meter(text):
    nums, den = text.split("/")
    return [int(n) for n in nums.split("+")], int(den)


def meter_duration(text):
    nums, den = parse_meter(text)
    return F(sum(nums), den)


def single_beat_unit(n, d):
    """music-theory BEAT-UNIT of (make-meter :numerators (list n) :denominator d)."""
    return F(3, d) if n > 3 and n % 3 == 0 else F(1, d)


def meter_beats(text):
    """music-theory METER-BEATS."""
    nums, den = parse_meter(text)
    if len(nums) > 1:
        return [F(n, den) for n in nums]
    n = nums[0]
    if n > 3 and n % 3 == 0:
        return [F(3, den)] * (n // 3)
    return [F(1, den)] * n


def meter_text(n, d):
    return f"{n}/{d}"


def tick(x, division):
    return math.floor(4 * division * x + F(1, 2))


def round_half_up(x):
    return math.floor(x + F(1, 2))


# --- the score -------------------------------------------------------------


def chord_text(sym):
    """print-chord-symbol in :pop for the qualities the fixtures use."""
    if sym.get("no-chord-p"):
        return "N.C."
    quality = {"major": "", "minor": "m", "dominant-7": "7", "minor-7": "m7",
               "major-7": "maj7"}[sym["quality"]]
    text = sym["root"] + quality
    alts = sym.get("alterations") or []
    if alts:
        text += "(" + ",".join(("b" if a < 0 else "#") + str(d) for d, a in alts) + ")"
    if sym.get("bass"):
        text += "/" + sym["bass"]
    return text


def load_symbol(node):
    k = {node.value[i].value: node.value[i + 1] for i in range(0, len(node.value), 2)}
    sym = {}
    for name in ("root", "bass", "text"):
        if name in k:
            sym[name] = k[name].value
    if "quality" in k:
        sym["quality"] = k["quality"].value
    if "no-chord-p" in k:
        sym["no-chord-p"] = True
    if "alterations" in k:
        sym["alterations"] = [(int(p.value[0].value), int(p.tail.value)) for p in items(k["alterations"])]
    return sym


def load_event(node):
    kind, k = plist(node)
    ev = {"kind": kind, "id": val(k, "id"), "duration": F(val(k, "duration")),
          "tuplet": val(k, "tuplet"), "grace": val(k, "grace"),
          "dynamic": plist(k["dynamic"])[1]["value"].value if "dynamic" in k else None,
          "lyrics": [], "notes": []}
    for lyr in items(k.get("lyrics")):
        _, lk = plist(lyr)
        ev["lyrics"].append({"verse": int(val(lk, "verse", 1)), "text": val(lk, "text"),
                             "syllabic": val(lk, "syllabic", "single"),
                             "extender": val(lk, "extender")})

    def tie_end(keys):
        return plist(keys["tie"])[1]["end"].value if "tie" in keys else None

    if kind == "note":
        ev["notes"] = [{"id": ev["id"], "pitch": val(k, "pitch"), "tie": tie_end(k)}]
    elif kind == "chord":
        for n in items(k["notes"]):
            _, nk = plist(n)
            ev["notes"].append({"id": val(nk, "id"), "pitch": val(nk, "pitch"), "tie": tie_end(nk)})
    return ev


class Score:
    def __init__(self, name, text):
        self.name = name
        node = parse(text)
        _, s = plist(node)
        md = items(s.get("metadata"))
        self.metadata = {md[i].value: md[i + 1].value for i in range(0, len(md), 2)}
        self.measures = []
        for m in items(s.get("measures")):
            _, k = plist(m)
            ending = None
            if "ending" in k:
                _, e = plist(k["ending"])
                ending = ([int(x.value) for x in items(e["passes"])], int(val(e, "measures", 1)))
            tempo = []
            for t in items(k.get("tempo")):
                _, tk = plist(t)
                tempo.append({"offset": F(val(tk, "offset", 0)), "bpm": val(tk, "bpm"),
                              "unit": F(val(tk, "beat-unit")) if "beat-unit" in tk else None,
                              "text": val(tk, "text")})
            self.measures.append({
                "time": val(k, "time"), "key": val(k, "key"), "pickup": bool(val(k, "pickup")),
                "length": F(val(k, "length")) if "length" in k else None,
                "repeat_start": bool(val(k, "repeat-start")), "repeat_end": val(k, "repeat-end"),
                "ending": ending, "jumps": [plist(j)[1]["kind"].value for j in items(k.get("jump"))],
                "rehearsal": plist(k["rehearsal"])[1]["text"].value if "rehearsal" in k else None,
                "tempo": tempo})
        self.parts = []
        for p in items(s.get("parts")):
            _, pk = plist(p)
            voices = []
            for v in items(pk.get("voices")):
                _, vk = plist(v)
                voices.append({"id": val(vk, "id"), "name": val(vk, "name"),
                               "measures": [[load_event(e) for e in items(vm)]
                                            for vm in items(vk.get("measures"))]})
            self.parts.append({"id": val(pk, "id"), "name": val(pk, "name"), "voices": voices})
        self.anchors = []
        for a in items(s.get("chord-symbols")):
            _, ak = plist(a)
            self.anchors.append({"bar": int(val(ak, "bar")), "offset": F(val(ak, "offset")),
                                 "symbol": load_symbol(ak["symbol"])})
        self.first_bar = 0 if self.measures and self.measures[0]["pickup"] else 1
        self.last_bar = self.first_bar + len(self.measures) - 1

    def measure(self, bar):
        return self.measures[bar - self.first_bar]

    def inherited(self, bar, slot, default):
        for i in range(bar - self.first_bar, -1, -1):
            if self.measures[i][slot]:
                return self.measures[i][slot]
        return default

    def bar_time(self, bar):
        return self.inherited(bar, "time", "4/4")

    def bar_key(self, bar):
        return self.inherited(bar, "key", "C major")

    def bar_length(self, bar):
        return self.measure(bar)["length"] or meter_duration(self.bar_time(bar))

    def voices(self):
        out = []
        for i, part in enumerate(self.parts):
            for j, voice in enumerate(part["voices"]):
                out.append((i, j, part, voice))
        return out


# --- the playing order: score-protocol's UNFOLD (SC1) ------------------------

DC_KINDS = ("da-capo", "da-capo-al-fine", "da-capo-al-coda",
            "dal-segno", "dal-segno-al-fine", "dal-segno-al-coda")


def endings_of(score):
    """(first last passes) of every ending, in written order."""
    out = []
    for i, m in enumerate(score.measures):
        if m["ending"]:
            bar = score.first_bar + i
            out.append((bar, min(score.last_bar, bar + m["ending"][1] - 1), m["ending"][0]))
    return out


def ending_groups(endings):
    groups = []
    for e in endings:
        if groups and groups[-1][-1][1] + 1 == e[0]:
            groups[-1].append(e)
        else:
            groups.append([e])
    return groups


def sections_of(score):
    """(start end times) per REPEAT-END bar, by the SC1 rules."""
    groups = ending_groups(endings_of(score))

    def g(e):
        for group in groups:
            if group[0][0] <= e <= group[-1][1] or group[0][0] == e + 1:
                return group[-1][1]
        return e

    sections, prev_g = [], score.first_bar - 1
    for i, m in enumerate(score.measures):
        bar = score.first_bar + i
        if m["repeat_end"]:
            starts = [b for b in range(prev_g + 1, bar + 1) if score.measure(b)["repeat_start"]]
            sections.append((starts[-1] if starts else prev_g + 1, bar, int(m["repeat_end"])))
            prev_g = g(bar)
    return sections


class NoSegno(Exception):
    pass


def playback_order(score):
    """score-protocol's UNFOLD walk (SC1, src/views.lisp there), restated to
    derive the export facts; tests/export-test.lisp checks it against UNFOLD."""
    if not score.measures:
        return []
    sections, endings = sections_of(score), endings_of(score)
    groups = ending_groups(endings)
    starts = {s[0] for s in sections}
    by_end = {s[1]: s for s in sections}
    last_of_group = {group[-1][0] for group in groups}
    b, pass_, jumped, mode, taken, counts, out = score.first_bar, 1, False, None, set(), {}, []
    by_repeat = False
    while b <= score.last_bar:
        ending = next((e for e in endings if e[0] == b), None)
        if ending and not (ending[0] in last_of_group if jumped else pass_ in ending[2]):
            b, by_repeat = ending[1] + 1, False
            continue
        if b in starts and not by_repeat:
            pass_ = 1
        counts[b] = counts.get(b, 0) + 1
        out.append((b, counts[b]))
        jumps = score.measure(b)["jumps"]
        sec = by_end.get(b)
        if sec and not jumped and pass_ < sec[2]:
            pass_ += 1
            b, by_repeat = sec[0], True
            continue
        by_repeat = False
        if "fine" in jumps and mode == "fine":
            break
        if "to-coda" in jumps and mode == "coda":
            coda = next((x for x in range(b + 1, score.last_bar + 1)
                         if "coda" in score.measure(x)["jumps"]), None)
            if coda is None:
                break
            b = coda
            continue
        dc = next((j for j in jumps if j in DC_KINDS and (b, j) not in taken), None)
        if dc:
            if dc.startswith("da-capo"):
                target = score.first_bar
            else:
                target = next((x for x in range(b, score.first_bar - 1, -1)
                               if "segno" in score.measure(x)["jumps"]), None)
                if target is None:
                    raise NoSegno(b)
            taken.add((b, dc))
            jumped = True
            mode = "fine" if dc.endswith("al-fine") else "coda" if dc.endswith("al-coda") else None
            b = target
            continue
        b += 1
    return out


# --- SCORE-TO-SMF (src/export.lisp) ----------------------------------------

CHANNELS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15]
VELOCITY = {"pppp": (8, "pppp"), "ppp": (20, "ppp"), "pp": (33, "pp"), "p": (49, "p"),
            "mp": (64, "mp"), "mf": (80, "mf"), "f": (96, "f"), "ff": (112, "ff"),
            "fff": (120, "fff"), "ffff": (127, "ffff"), "fp": (96, "p"), "sfp": (112, "p"),
            "sf": (112, None), "sfz": (112, None), "fz": (112, None), "rf": (104, None),
            "rfz": (104, None)}
LOSSES = ["ids", "grace notes", "tick rounding", "pitch range", "tempo range", "shared channels"]
PREFIX_CHORD = "chord:"


def signature(score, bar):
    nums, den = parse_meter(score.bar_time(bar))
    length = score.bar_length(bar)
    if length == F(sum(nums), den):
        return sum(nums), den
    d = den
    while (length * d).denominator != 1:
        d *= 2
    return int(length * d), d


def export(score, division=480, layout="voice", program=52, programs=None, mix=None,
           unfold=True, verse=1, chord_symbols="text", default_dynamic="mf"):
    """(tracks, facts, losses): tracks as lists of (tick, message-spec)."""
    programs, mix = programs or {}, mix or {}
    if unfold is True:
        played = playback_order(score)
    elif unfold is None or unfold is False:
        played = [(b, 1) for b in range(score.first_bar, score.last_bar + 1)]
    else:
        played = unfold
    starts, u = [], F(0)
    for b, _ in played:
        starts.append(u)
        u += score.bar_length(b)
    end = u
    losses = {"ids"}

    def t(x):
        if (4 * division * x).denominator != 1:
            losses.add("tick rounding")
        return tick(x, division)

    # Conductor.
    cond = []

    def put(track, at, cat, sub, msg):
        track.append(((at, cat, sub, len(track)), msg))

    if "title" in score.metadata:
        put(cond, 0, 1, 0, ("track_name", score.metadata["title"]))
    if "copyright" in score.metadata:
        put(cond, 0, 1, 0, ("copyright", score.metadata["copyright"]))
    prev = None
    facts_ts, facts_ks, facts_tempo, facts_markers, facts_chords = [], [], [], [], []
    for j, (b, _) in enumerate(played):
        sig = signature(score, b)
        if j == 0 or sig != prev:
            n, d = sig
            cc = max(1, math.floor(96 * single_beat_unit(n, d)))
            at = t(starts[j])
            put(cond, at, 2, 0, ("time_signature", n, d, cc, 8))
            facts_ts.append([at, n, d, cc])
        prev = sig
    prev = None
    for j, (b, _) in enumerate(played):
        key = score.bar_key(b)
        if j == 0 or key != prev:
            at = t(starts[j])
            put(cond, at, 3, 0, ("key_signature", key_sharps(key), parse_key(key)[1] == "minor"))
            facts_ks.append([at, key_sharps(key), parse_key(key)[1] == "minor"])
        prev = key
    if played and not any(tm["bpm"] is not None and tm["offset"] == 0
                          for tm in score.measure(played[0][0])["tempo"]):
        put(cond, 0, 4, 0, ("set_tempo", 500000))
        facts_tempo.append([0, 500000])
    for j, (b, _) in enumerate(played):
        for tm in score.measure(b)["tempo"]:
            if tm["bpm"] is None:
                continue
            us = round_half_up(F(15000000) / (F(tm["bpm"]) * tm["unit"]))
            if not 1 <= us <= 16777215:
                losses.add("tempo range")
                us = min(16777215, max(1, us))
            at = t(starts[j] + tm["offset"])
            put(cond, at, 4, 0, ("set_tempo", us))
            facts_tempo.append([at, us])
    for j, (b, _) in enumerate(played):
        if score.measure(b)["rehearsal"]:
            at = t(starts[j])
            put(cond, at, 5, 0, ("marker", score.measure(b)["rehearsal"]))
            facts_markers.append([at, score.measure(b)["rehearsal"]])
    if chord_symbols:
        for j, (b, _) in enumerate(played):
            for a in score.anchors:
                if a["bar"] == b:
                    at = t(starts[j] + a["offset"])
                    text = PREFIX_CHORD + chord_text(a["symbol"])
                    put(cond, at, 6, 0, ("text" if chord_symbols == "text" else "marker", text))
                    facts_chords.append([at, text])

    # Voices.
    voices = score.voices()
    if len(voices) > 15:
        losses.add("shared channels")
    voice_facts, voice_events = [], []
    for k, (i, j, part, voice) in enumerate(voices):
        channel = CHANNELS[k % 15]
        plabel = part["name"] or f"Part {i + 1}"
        vlabel = voice["name"] or (plabel if len(part["voices"]) == 1 else f"{plabel} {j + 1}")
        prog = programs.get(voice["id"], programs.get(part["id"], program))
        entry = mix.get(voice["id"], mix.get(part["id"], {}))
        volume, pan, boost = entry.get("volume", 100), entry.get("pan", 64), entry.get("velocity", 0)
        seq = []
        for jj, (b, p) in enumerate(played):
            idx = b - score.first_bar
            if idx >= len(voice["measures"]) or idx >= len(score.measures):
                continue
            off = F(0)
            for ev in voice["measures"][idx]:
                if ev["grace"]:
                    losses.add("grace notes")
                    continue
                seq.append((starts[jj] + off, ev, p))
                off += ev["duration"]
        level, vels = default_dynamic, []
        for on, ev, p in seq:
            if ev["dynamic"]:
                vel, after = VELOCITY[ev["dynamic"]]
                if after:
                    level = after
            else:
                vel = VELOCITY[level][0]
            vels.append(min(127, max(1, vel + boost)))
        continued, notes, lyrics, spellings, chord_ties = set(), [], [], [], set()
        for idx, (on, ev, p) in enumerate(seq):
            seen = set()
            for n in ev["notes"]:
                key = midi_of(n["pitch"])
                if key in seen:
                    continue
                seen.add(key)
                if (idx, n["id"]) in continued:
                    continue
                stop, cur, ci = on + ev["duration"], n, idx
                while cur["tie"] and ci + 1 < len(seq):
                    non, nev, _ = seq[ci + 1]
                    target = next((m for m in nev["notes"] if m["id"] == cur["tie"]), None)
                    if non != stop or target is None or midi_of(target["pitch"]) != key:
                        break
                    continued.add((ci + 1, target["id"]))
                    if seq[ci][1]["kind"] == "chord" or nev["kind"] == "chord":
                        chord_ties.add((non, key))
                    stop, cur, ci = non + nev["duration"], target, ci + 1
                if not 0 <= key <= 127:
                    losses.add("pitch range")
                    continue
                a, z = t(on), t(stop)
                if z <= a:
                    z = a + 1
                notes.append([a, z, key, vels[idx]])
                bar = played[[x for x in range(len(played)) if starts[x] <= on][-1]][0]
                spellings.append([a, key, n["pitch"], pitch_in_k(n["pitch"], score.bar_key(bar))])
            if ev["kind"] != "rest" and verse is not None:
                v = p if verse == "pass" else verse
                for lyr in ev["lyrics"]:
                    if lyr["verse"] == v:
                        text = lyr["text"] + ("-" if lyr["syllabic"] in ("begin", "middle") else "")
                        lyrics.append([t(on), text, Kw(lyr["syllabic"])])
        notes.sort(key=lambda r: (r[0], r[2]))
        spellings.sort(key=lambda r: (r[0], r[1]))
        voice_facts.append({"id": voice["id"], "label": vlabel, "part": plabel, "channel": channel,
                            "program": prog, "volume": volume, "pan": pan, "notes": notes,
                            "lyrics": lyrics, "spellings": spellings, "k": k, "i": i,
                            "chord_ties": chord_ties})
    tracks = [cond]

    def voice_track(vfs, name, instrument):
        tr = []
        put(tr, 0, 1, 0, ("track_name", name))
        put(tr, 0, 1, 0, ("instrument_name", instrument))
        for vf in vfs:
            put(tr, 0, 1, 0, ("program_change", vf["channel"], vf["program"]))
            put(tr, 0, 1, 0, ("control_change", vf["channel"], 7, vf["volume"]))
            put(tr, 0, 1, 0, ("control_change", vf["channel"], 10, vf["pan"]))
        for vf in vfs:
            for a, z, key, vel in vf["notes"]:
                put(tr, z, 2, (vf["channel"], key), ("note_off", vf["channel"], key, 0))
                put(tr, a, 4, (vf["channel"], key), ("note_on", vf["channel"], key, vel))
            for at, text, _ in vf["lyrics"]:
                put(tr, at, 3, (vf["k"], 0), ("lyrics", text))
        return tr

    if layout == "voice":
        for vf in voice_facts:
            tracks.append(voice_track([vf], vf["label"], vf["part"]))
    else:
        for i, part in enumerate(score.parts):
            vfs = [vf for vf in voice_facts if vf["i"] == i]
            label = part["name"] or f"Part {i + 1}"
            tracks.append(voice_track(vfs, label, label))
    end_tick = tick(end, division)
    facts = {"bars": [[b, p, tick(starts[j], division)] for j, (b, p) in enumerate(played)],
             "end": end_tick, "time-signatures": facts_ts, "key-signatures": facts_ks,
             "tempos": facts_tempo, "markers": facts_markers, "chords": facts_chords,
             "voices": voice_facts, "losses": [x for x in LOSSES if x in losses],
             "played": played, "starts": starts}
    return tracks, end_tick, facts


MIDO_KEYS = {}


def mido_key(sharps, minor):
    majors = ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"]
    minors = ["Abm", "Ebm", "Bbm", "Fm", "Cm", "Gm", "Dm", "Am", "Em", "Bm", "F#m", "C#m",
              "G#m", "D#m", "A#m"]
    return (minors if minor else majors)[sharps + 7]


def mido_message(spec, delta):
    import mido
    kind = spec[0]
    if kind in ("track_name", "copyright", "instrument_name", "marker", "text", "lyrics"):
        return mido.MetaMessage(kind, text=spec[1], time=delta) if kind not in (
            "track_name", "instrument_name") else mido.MetaMessage(kind, name=spec[1], time=delta)
    if kind == "time_signature":
        return mido.MetaMessage("time_signature", numerator=spec[1], denominator=spec[2],
                                clocks_per_click=spec[3], notated_32nd_notes_per_beat=spec[4],
                                time=delta)
    if kind == "key_signature":
        return mido.MetaMessage("key_signature", key=mido_key(spec[1], spec[2]), time=delta)
    if kind == "set_tempo":
        return mido.MetaMessage("set_tempo", tempo=spec[1], time=delta)
    if kind == "program_change":
        return mido.Message("program_change", channel=spec[1], program=spec[2], time=delta)
    if kind == "control_change":
        return mido.Message("control_change", channel=spec[1], control=spec[2], value=spec[3],
                            time=delta)
    if kind in ("note_on", "note_off"):
        return mido.Message(kind, channel=spec[1], note=spec[2], velocity=spec[3], time=delta)
    raise ValueError(spec)


def smf_bytes(tracks, end_tick, division, fmt=1):
    """mido's encoding of TRACKS: each sorted by its keys (tick, category, ...),
    then deltas, then one end of track at the largest tick."""
    import mido
    mf = mido.MidiFile(type=fmt, ticks_per_beat=division)
    for tr in tracks:
        events = sorted(tr, key=lambda e: e[0])
        last = max([end_tick] + [e[0][0] for e in events])
        track, prev = mido.MidiTrack(), 0
        for (at, *_), spec in events:
            track.append(mido_message(spec, at - prev))
            prev = at
        track.append(mido.MetaMessage("end_of_track", time=last - prev))
        mf.tracks.append(track)
    out = io.BytesIO()
    mf.save(file=out)
    return out.getvalue()


# --- the import's measure map (src/measures.lisp), for files we wrote --------


def import_measure_map(time_sigs, key_sigs, tempos, markers, end, division):
    """The measure map SMF-TO-SCORE builds from these meta events (ticks), as
    rows (length time key pickup tempo-marks rehearsal)."""
    w = lambda tk: F(tk, 4 * division)
    sigs = sorted({ts[0]: (ts[1], ts[2]) for ts in time_sigs}.items()) or [(0, (4, 4))]
    if sigs[0][0] != 0:
        sigs.insert(0, (0, (4, 4)))
    bars, pos, run = [], F(0), -1
    E = w(end)
    sig_points = [(w(at), s) for at, s in sigs]
    current, si = None, 0
    while pos < E or not bars:
        while si < len(sig_points) and sig_points[si][0] <= pos:
            current, run, si = sig_points[si][1], run + 1, si + 1
        length = F(current[0], current[1])
        stop = pos + length
        if si < len(sig_points) and sig_points[si][0] < stop:
            stop = sig_points[si][0]
        bars.append({"start": pos, "length": stop - pos, "sig": current, "run": run})
        pos = stop
        if E == 0:
            break
    m = len(bars)
    meters = [b["sig"] for b in bars]
    alone = lambda i: sum(1 for b in bars if b["run"] == bars[i]["run"]) == 1
    pickup = (m >= 2 and alone(0) and bars[0]["length"] < F(bars[1]["sig"][0], bars[1]["sig"][1]))
    if pickup:
        meters[0] = bars[1]["sig"]
    if m >= 2 and alone(m - 1) and bars[m - 1]["length"] < F(bars[m - 2]["sig"][0], bars[m - 2]["sig"][1]):
        meters[m - 1] = bars[m - 2]["sig"]
    rows = []
    for i, b in enumerate(bars):
        n, d = meters[i]
        time = meter_text(n, d) if i == 0 or meters[i] != meters[i - 1] else None
        length = b["length"] if b["length"] != F(n, d) else None
        key = None
        for at, sharps, minor in key_sigs:
            if b["start"] <= w(at) < b["start"] + b["length"]:
                key = key_of_sharps(sharps, minor)
        unit = single_beat_unit(n, d)
        marks = []
        for at, us in tempos:
            if b["start"] <= w(at) < b["start"] + b["length"]:
                bpm = F(round_half_up(F(100 * 15000000) / (us * unit)), 100)
                marks = [mk for mk in marks if mk[0] != w(at) - b["start"]]
                marks.append([w(at) - b["start"], bpm, unit])
        reh = next((text for at, text in markers
                    if b["start"] <= w(at) < b["start"] + b["length"]), None)
        rows.append([length, time, key, pickup and i == 0, marks, reh])
    return rows


# --- music21 cross-check ---------------------------------------------------


def m21_pitch(name):
    letter, alter, octave = split_pitch(name)
    return letter + {0: "", 1: "#", 2: "##", -1: "-", -2: "--"}[alter] + str(octave)


def music21_voice(score, voice):
    """music21's sounding notes of VOICE: (onset, end, midi) in whole notes after
    expandRepeats and stripTies, the bar order, and the tempo marks."""
    from music21 import stream, note, chord, meter, key, tempo, bar, spanner, repeat, tie, duration
    part = stream.Part()
    ms = []
    pending_ties = {}
    for i, mm in enumerate(score.measures):
        b = score.first_bar + i
        m = stream.Measure(number=i + 1)
        m.groups.append(f"bar{b}")
        if mm["time"]:
            m.insert(0, meter.TimeSignature(mm["time"]))
        if mm["key"]:
            tonic, mode = parse_key(mm["key"])
            m.insert(0, key.Key(m21_pitch(tonic + "4")[:-1], mode))
        for tm in mm["tempo"]:
            if tm["bpm"] is not None:
                m.insert(float(tm["offset"] * 4),
                         tempo.MetronomeMark(number=float(tm["bpm"]),
                                             referent=duration.Duration(float(tm["unit"] * 4))))
        if mm["repeat_start"]:
            m.leftBarline = bar.Repeat(direction="start")
        if mm["repeat_end"]:
            m.rightBarline = bar.Repeat(direction="end", times=int(mm["repeat_end"]))
        for jk in mm["jumps"]:
            if jk == "segno":
                m.insert(0, repeat.Segno())
            elif jk == "coda":
                m.insert(0, repeat.Coda())
        events = voice["measures"][i] if i < len(voice["measures"]) else []
        off = F(0)
        for ev in events:
            if ev["grace"]:
                continue
            ql = ev["duration"] * 4
            if ev["kind"] == "rest":
                obj = note.Rest(quarterLength=ql)
            elif ev["kind"] == "note":
                obj = note.Note(m21_pitch(ev["notes"][0]["pitch"]), quarterLength=ql)
            else:
                obj = chord.Chord([m21_pitch(n["pitch"]) for n in ev["notes"]], quarterLength=ql)
            for n in ev["notes"]:
                state = []
                if n["id"] in pending_ties:
                    state.append("stop")
                if n["tie"]:
                    state.append("start")
                    pending_ties[n["tie"]] = True
                if state:
                    kind = "continue" if len(state) == 2 else state[0]
                    if ev["kind"] == "chord":
                        obj.setTie(tie.Tie(kind), m21_pitch(n["pitch"]))
                    else:
                        obj.tie = tie.Tie(kind)
            m.insert(float(off * 4), obj)
            off += ev["duration"]
        if not events or off < score.bar_length(b):
            m.insert(float(off * 4), note.Rest(quarterLength=(score.bar_length(b) - off) * 4,
                                               hideObjectOnPrint=True))
        for jk in mm["jumps"]:
            cls = {"to-coda": lambda: repeat.Coda("To Coda"), "fine": repeat.Fine,
                   "da-capo": repeat.DaCapo, "da-capo-al-fine": repeat.DaCapoAlFine,
                   "da-capo-al-coda": repeat.DaCapoAlCoda, "dal-segno": repeat.DalSegno,
                   "dal-segno-al-fine": repeat.DalSegnoAlFine,
                   "dal-segno-al-coda": repeat.DalSegnoAlCoda}.get(jk)
            if cls:
                m.append(cls())
        ms.append(m)
    for i, m in enumerate(ms):
        if i == 0 and score.measures[0]["pickup"]:
            m.paddingLeft = float(meter_duration(score.bar_time(score.first_bar)) * 4 - m.highestTime)
        part.append(m)
    for b0, b1, passes in endings_of(score):
        part.insert(0, spanner.RepeatBracket([ms[b - score.first_bar] for b in range(b0, b1 + 1)],
                                             number=", ".join(str(p) for p in passes)))
    structured = any(m["repeat_end"] or m["jumps"] for m in score.measures)
    expanded = part.expandRepeats() if structured else part
    order = [int(g[3:]) for m in expanded.getElementsByClass(stream.Measure)
             for g in m.groups if g.startswith("bar")]
    stripped = expanded.stripTies(matchByPitch=True)
    notes = []
    for n in stripped.flatten().notes:
        on = F(n.getOffsetInHierarchy(stripped)).limit_denominator(10000) / 4
        dur = F(n.quarterLength).limit_denominator(10000) / 4
        for p in n.pitches:
            notes.append((on, on + dur, p.midi))
    tempos = []
    for mm in stripped.flatten().getElementsByClass(tempo.MetronomeMark):
        tempos.append((F(mm.getOffsetInHierarchy(stripped)).limit_denominator(10000) / 4,
                       mm.secondsPerQuarter() * 1e6))
    return sorted(set(notes)), order, tempos


def check_with_music21(score, facts, division):
    starts = facts["starts"]
    ours_order = [b for b, _ in facts["played"]]
    for vf, (_, _, _, voice) in zip(facts["voices"], score.voices()):
        notes, order, tempos = music21_voice(score, voice)
        if order and order != ours_order:
            raise SystemExit(f"{score.name}: music21 plays bars {order}, the rules {ours_order}")
        ours = sorted({(F(a, 4 * division), F(z, 4 * division), key) for a, z, key, _ in vf["notes"]})
        # music21's stripTies leaves a tie between single notes of two chords
        # unjoined: join those segments where the fixture ties a chord note.
        joined = sorted(notes)
        for at, key in sorted(vf["chord_ties"]):
            first = next(n for n in joined if n[1] == at and n[2] == key)
            second = next(n for n in joined if n[0] == at and n[2] == key)
            joined.remove(first)
            joined.remove(second)
            joined.append((first[0], second[1], key))
            joined.sort()
        theirs = sorted({(F(tick(a, division), 4 * division), F(tick(z, division), 4 * division), key)
                         for a, z, key in joined})
        if ours != theirs:
            raise SystemExit(f"{score.name} {vf['id']}: music21 notes differ:\n {ours}\n {theirs}")
        ours_t = [(F(at, 4 * division), us) for at, us in facts["tempos"] if not (at == 0 and us == 500000)]
        for (at, us), (mat, mus) in zip(ours_t, tempos):
            if at != mat or abs(us - mus) > 1:
                raise SystemExit(f"{score.name}: tempo {at} {us} vs music21 {mat} {mus}")
    return True


# --- QUANTIZE-ONSETS (src/quantize.lisp) -------------------------------------

SUBDIVISIONS = [1, 2, 3, 4, 6, 8]
WEIGHTS = {"deviation": 1000, "level": 50, "tuplet": 30}
OMEGA = {1: 0, 2: 1, 3: 1, 4: 2, 6: 2, 8: 3}
TUPLETS = {"simple": {3: F(3, 2), 6: F(3, 2)}, "dotted": {2: F(2, 3), 4: F(2, 3), 8: F(2, 3)}}


def beat_kind(unit):
    return "dotted" if unit.numerator == 3 else "simple"


def grid_points(beat, s):
    start, end, unit = beat
    h = unit / s
    pts, k = [], 0
    while start + k * h < end:
        pts.append(start + k * h)
        k += 1
    pts.append(end)
    return pts


def snap(x, beat, s):
    pts = grid_points(beat, s)
    best = None
    for p in pts:
        if best is None or abs(x - p) < abs(x - best) or (abs(x - p) == abs(x - best) and p > best):
            best = p
    return best


def beat_index(x, beats):
    for i, (start, end, _) in enumerate(beats):
        if start <= x < end:
            return i
    if x == beats[-1][1]:
        return len(beats) - 1
    raise ValueError(x)


def complexity(beat, s):
    return WEIGHTS["level"] * OMEGA[s] + (WEIGHTS["tuplet"] if s in TUPLETS[beat_kind(beat[2])] else 0)


def quantize(onsets, beats, subdivisions=SUBDIVISIONS, exact=False):
    by_beat = [[] for _ in beats]
    for o in onsets:
        by_beat[beat_index(o, beats)].append(o)
    choices, margins = [], []
    for beat, os_ in zip(beats, by_beat):
        allowed = subdivisions
        if exact:
            allowed = [s for s in subdivisions if all(snap(o, beat, s) == o for o in os_)]
            if not allowed:
                choices.append(None)
                margins.append(None)
                continue
        costs = sorted((sum(round_half_up(WEIGHTS["deviation"] * abs(o - snap(o, beat, s)) / beat[2])
                            for o in os_) + complexity(beat, s), subdivisions.index(s), s)
                       for s in allowed)
        choices.append(costs[0][2])
        margins.append(costs[1][0] - costs[0][0] if len(costs) > 1 else None)
    positions, confidences = [], []
    for o in onsets:
        i = beat_index(o, beats)
        if exact:
            positions.append(o)
            confidences.append(F(1))
        else:
            s = choices[i]
            p = snap(o, beats[i], s)
            h = beats[i][2] / s
            positions.append(p)
            m = F(1) if margins[i] is None else min(F(1), F(margins[i], WEIGHTS["level"]))
            confidences.append(min(1 - (2 * abs(o - p) / h) ** 2, m))
    return choices, positions, confidences


def bar_beats(start, length, meter):
    """The import's beats of a bar (src/import.lisp, Beats)."""
    out, pos = [], start
    for unit in meter_beats(meter):
        if pos >= start + length:
            break
        out.append((pos, min(pos + unit, start + length), unit))
        pos += unit
    return out


def quantize_rows():
    rows = []
    rng = random.Random(20261124)
    layouts = {
        "4/4": [(F(i, 4), F(i + 1, 4), F(1, 4)) for i in range(4)],
        "6/8": [(F(0), F(3, 8), F(3, 8)), (F(3, 8), F(3, 4), F(3, 8))],
        "3/4 pickup": [(F(0), F(1, 4), F(1, 4)), (F(1, 4), F(1, 2), F(1, 4)), (F(1, 2), F(3, 4), F(1, 4))],
        "2/2": [(F(0), F(1, 2), F(1, 2)), (F(1, 2), F(1), F(1, 2))],
        "cut 6/8": [(F(0), F(1, 4), F(3, 8))],
    }
    hand = [
        ("straight eighths", "4/4", [F(0), F(1, 8), F(1, 4), F(3, 8)]),
        ("triplet eighths", "4/4", [F(0), F(1, 12), F(1, 6), F(1, 4)]),
        ("swing", "4/4", [F(0), F(31, 192), F(1, 4), F(79, 192)]),
        ("sixteenths", "4/4", [F(0), F(1, 16), F(1, 8), F(3, 16)]),
        ("dotted rhythm", "4/4", [F(0), F(3, 16), F(1, 4)]),
        ("early", "4/4", [F(239, 960), F(1, 2) - F(1, 160)]),
        ("empty beats", "4/4", [F(0)]),
        ("compound eighths", "6/8", [F(0), F(1, 8), F(1, 4), F(3, 8), F(1, 2), F(5, 8)]),
        ("duplet", "6/8", [F(0), F(3, 16), F(3, 8)]),
        ("half-note beat triplets", "2/2", [F(0), F(1, 6), F(1, 3), F(1, 2)]),
        ("cut beat", "cut 6/8", [F(0), F(1, 8), F(1, 4)]),
        ("pickup", "3/4 pickup", [F(0), F(1, 4), F(3, 8), F(1, 2)]),
    ]
    for label, layout, onsets in hand:
        rows.append(qrow(label, layouts[layout], onsets, SUBDIVISIONS, False))
    for label, layout, onsets in hand[:6] + hand[7:]:
        rows.append(qrow(label + " (exact)", layouts[layout], onsets, SUBDIVISIONS, True))
    rows.append(qrow("straight only", layouts["4/4"], [F(0), F(1, 12), F(1, 6)], [1, 2, 4], False))
    rows.append(qrow("triplets first", layouts["4/4"], [F(0), F(1, 8)], [3, 2, 1], False))
    for n in range(40):
        layout = rng.choice(["4/4", "6/8", "2/2", "3/4 pickup"])
        beats = layouts[layout]
        onsets = []
        for beat in beats:
            s = rng.choice([1, 2, 2, 3, 4, 4, 6])
            for k in range(s):
                if rng.random() < 0.6:
                    x = beat[0] + k * beat[2] / s + F(rng.randint(-60, 60), 4800)
                    if beats[0][0] <= x < beats[-1][1]:
                        onsets.append(x)
        subs = SUBDIVISIONS if n % 5 else [2, 4, 3, 1]
        rows.append(qrow(f"random {n}", beats, sorted(set(onsets)), subs, n % 7 == 3))
    return rows


def qrow(label, beats, onsets, subs, exact):
    if exact:
        # Exact rows use onsets on some grid of each beat.
        onsets = [o for o in onsets]
    choices, positions, confidences = quantize(onsets, beats, subs, exact)
    return [label, [list(b) for b in beats], onsets, subs, exact, choices, positions, confidences]


# --- performances (sc4-perf-*.mid) -----------------------------------------

MELODIES = [
    ("amazing-grace", "Amazing Grace (tune 1829)", "3/4", "G major", 72, F(1, 4),
     "D4:1/4 G4:1/2 B4:1/8 G4:1/8 B4:1/2 A4:1/4 G4:1/2 E4:1/4 D4:1/2 D4:1/4 G4:1/2 B4:1/8 G4:1/8 "
     "B4:1/2 A4:1/8 B4:1/8 D5:3/4"),
    ("old-hundredth", "Old Hundredth (Genevan Psalter, 1551)", "4/4", "G major", 84, F(0),
     "G4:1/4 G4:1/4 F#4:1/4 E4:1/4 D4:1/2 G4:1/4 A4:1/4 B4:1/4 B4:1/4 B4:1/4 A4:1/4 "
     "G4:1/2 C5:1/4 B4:1/4 A4:1/4 G4:1/4 A4:1/4 F#4:1/4 G4:1"),
    ("twinkle", "Ah! vous dirai-je, maman (18th c.)", "4/4", "C major", 100, F(0),
     "C4:1/4 C4:1/4 G4:1/4 G4:1/4 A4:1/4 A4:1/4 G4:1/2 F4:1/4 F4:1/4 E4:1/4 E4:1/4 "
     "D4:1/4 D4:1/4 C4:1/2 G4:1/4 G4:1/4 F4:1/4 F4:1/4 E4:1/4 E4:1/4 D4:1/2"),
    ("ode-to-joy", "Ode to Joy (Beethoven, 1824)", "4/4", "D major", 108, F(0),
     "F#4:1/4 F#4:1/4 G4:1/4 A4:1/4 A4:1/4 G4:1/4 F#4:1/4 E4:1/4 D4:1/4 D4:1/4 E4:1/4 F#4:1/4 "
     "F#4:3/8 E4:1/8 E4:1/2 F#4:1/4 F#4:1/4 G4:1/4 A4:1/4 A4:1/4 G4:1/4 F#4:1/4 E4:1/4 "
     "D4:1/4 D4:1/4 E4:1/4 F#4:1/4 E4:3/8 D4:1/8 D4:1/2"),
    ("frere-jacques", "Frere Jacques (trad.)", "4/4", "F major", 120, F(0),
     "F4:1/4 G4:1/4 A4:1/4 F4:1/4 F4:1/4 G4:1/4 A4:1/4 F4:1/4 A4:1/4 Bb4:1/4 C5:1/2 "
     "A4:1/4 Bb4:1/4 C5:1/2 C5:1/8 D5:1/8 C5:1/8 Bb4:1/8 A4:1/4 F4:1/4 "
     "C5:1/8 D5:1/8 C5:1/8 Bb4:1/8 A4:1/4 F4:1/4 F4:1/4 C4:1/4 F4:1/2 F4:1/4 C4:1/4 F4:1/2"),
    ("silent-night", "Stille Nacht (Gruber, 1818)", "6/8", "Bb major", 56, F(0),
     "F4:3/16 G4:1/16 F4:1/8 D4:3/8 F4:3/16 G4:1/16 F4:1/8 D4:3/8 C5:1/4 C5:1/8 A4:3/8 "
     "Bb4:1/4 Bb4:1/8 F4:3/8 G4:1/4 G4:1/8 Bb4:3/16 A4:1/16 G4:1/8 F4:3/16 G4:1/16 F4:1/8 D4:3/8"),
    ("row-your-boat", "Row, Row, Row Your Boat (1852)", "6/8", "C major", 60, F(0),
     "C4:3/8 C4:3/8 C4:1/4 D4:1/8 E4:3/8 E4:1/4 D4:1/8 E4:1/4 F4:1/8 G4:3/4 "
     "C5:1/8 C5:1/8 C5:1/8 G4:1/8 G4:1/8 G4:1/8 E4:1/8 E4:1/8 E4:1/8 C4:1/8 C4:1/8 C4:1/8 "
     "G4:1/4 F4:1/8 E4:1/4 D4:1/8 C4:3/4"),
    ("minuet-in-g", "Minuet in G (Petzold, c. 1725)", "3/4", "G major", 112, F(0),
     "D5:1/4 G4:1/8 A4:1/8 B4:1/8 C5:1/8 D5:1/4 G4:1/4 G4:1/4 E5:1/4 C5:1/8 D5:1/8 E5:1/8 F#5:1/8 "
     "G5:1/4 G4:1/4 G4:1/4 C5:1/4 D5:1/8 C5:1/8 B4:1/8 A4:1/8 B4:1/4 C5:1/8 B4:1/8 A4:1/8 G4:1/8 "
     "F#4:1/4 G4:1/8 A4:1/8 B4:1/8 G4:1/8 A4:3/4"),
    ("triplet-study", "Triplet Study (written for these tests)", "4/4", "F major", 88, F(0),
     "F4:1/12 G4:1/12 A4:1/12 Bb4:1/4 C5:1/12 D5:1/12 C5:1/12 A4:1/4 "
     "G4:1/8 A4:1/8 Bb4:1/12 C5:1/12 Bb4:1/12 A4:1/4 G4:1/4 "
     "F4:1/12 A4:1/12 C5:1/12 F5:1/4 E5:1/12 D5:1/12 C5:1/12 Bb4:1/4 A4:1/6 G4:1/12 F4:1/4 F4:1/2"),
    ("jingle-bells", "Jingle Bells (Pierpont, 1857)", "4/4", "G major", 120, F(0),
     "B4:1/4 B4:1/4 B4:1/2 B4:1/4 B4:1/4 B4:1/2 B4:1/4 D5:1/4 G4:3/8 A4:1/8 B4:1 "
     "C5:1/4 C5:1/4 C5:3/8 C5:1/8 C5:1/4 B4:1/4 B4:1/4 B4:1/8 B4:1/8 B4:1/4 A4:1/4 A4:1/4 B4:1/4 "
     "A4:1/2 D5:1/2"),
]
DIVISION_PERF = 480


def melody_notes(text):
    out = []
    for tok in text.split():
        pitch, dur = tok.split(":")
        out.append((pitch, F(dur)))
    return out


def performance(index, entry):
    """A humanised rendering (tempo, time and key signature in a conductor
    track, the melody in a second): the notated melody placed after a padding that
    puts its pickup in the right beat, onsets moved by gaussian timing errors,
    notes held 60-100% of their value, velocities around 80."""
    name, title, meter, key, bpm, pickup, text = entry
    rng = random.Random(1000 + index)
    bar = meter_duration(meter)
    pad = (bar - pickup) % bar
    sigma = [0.02, 0.025, 0.03, 0.04, 0.07][index % 5]
    truth, rendered, pos = [], [], pad
    for pitch, dur in melody_notes(text):
        truth.append((pos, pos + dur, pitch))
        on = tick(pos, DIVISION_PERF) + round(rng.gauss(0, sigma) * DIVISION_PERF)
        hold = dur * F(rng.randint(60, 100), 100)
        off = tick(pos + hold, DIVISION_PERF) + round(rng.gauss(0, sigma / 2) * DIVISION_PERF)
        rendered.append([max(0, on), max(max(0, on) + 20, off), midi_of(pitch), rng.randint(64, 96)])
        pos += dur
    for i in range(1, len(rendered)):
        rendered[i][0] = max(rendered[i][0], rendered[i - 1][0] + 10)
        rendered[i][1] = max(rendered[i][1], rendered[i][0] + 20)
    total = pos
    return truth, rendered, total, pad


def import_performance(rendered, meter, total_end_tick):
    """SMF-TO-SCORE of a one-melody file (one time signature, the key signature
    of the melody's key): the notes as (start end key q) from the rules of
    import.lisp. Every note is in the key, so its confidence is its start's."""
    w = lambda tk: F(tk, 4 * DIVISION_PERF)
    E_raw = w(total_end_tick)
    bar = meter_duration(meter)
    nbars = max(1, math.ceil(E_raw / bar))
    E = nbars * bar
    beats = []
    for b in range(nbars):
        beats += bar_beats(b * bar, bar, meter)
    lcm = 24
    exact = all(((w(x) - beats[beat_index(w(x), beats)][0]) * lcm / beats[beat_index(w(x), beats)][2]).denominator == 1
                for note in rendered for x in note[:2])
    assert not exact
    starts = sorted({w(n[0]) for n in rendered})
    choices, positions, confidences = quantize(starts, beats)
    # 0.1.1 (issue #3): a start snapped to E, which no bar holds, moves back to
    # the last point of the last beat's grid below E, its q at most 1/2.
    late = grid_points(beats[-1], choices[-1])[-2]
    confidences = [min(q, F(1, 2)) if p == E else q for p, q in zip(positions, confidences)]
    positions = [late if p == E else p for p in positions]
    snapped = dict(zip(starts, positions))
    qconf = dict(zip(starts, confidences))
    notes = [[snapped[w(on)], w(off), key, qconf[w(on)]] for on, off, key, _ in rendered]
    single = len({n[0] for n in notes}) == len(notes)
    assert single
    order = sorted(set(n[0] for n in notes))
    out = []
    for n in notes:
        start, end, key, q = n
        nxt = next((s for s in order if s > start), E)
        end = min(end, nxt)
        if end != E:
            bi = beat_index(end, beats)
            end = snap(end, beats[bi], choices[bi])
        if end <= start:
            bi = beat_index(start, beats)
            end = min(start + beats[bi][2] / choices[bi], nxt)
        out.append([start, end, key, q])
    return out, E, choices, beats


def performance_rows():
    import mido
    rows = []
    for index, entry in enumerate(MELODIES):
        name, title, meter, key, bpm, pickup, text = entry
        truth, rendered, total, pad = performance(index, entry)
        n, d = parse_meter(meter)[0][0], parse_meter(meter)[1]
        mf = mido.MidiFile(type=1, ticks_per_beat=DIVISION_PERF)
        cond = mido.MidiTrack()
        unit = single_beat_unit(n, d)
        cond.append(mido.MetaMessage("set_tempo", tempo=round_half_up(F(15000000) / (bpm * unit)), time=0))
        cond.append(mido.MetaMessage("time_signature", numerator=n, denominator=d,
                                     clocks_per_click=max(1, math.floor(96 * unit)),
                                     notated_32nd_notes_per_beat=8, time=0))
        cond.append(mido.MetaMessage("key_signature",
                                     key=mido_key(key_sharps(key), parse_key(key)[1] == "minor"), time=0))
        mf.tracks.append(cond)
        events = []
        for on, off, k, vel in rendered:
            events.append((on, 1, mido.Message("note_on", channel=0, note=k, velocity=vel)))
            events.append((off, 0, mido.Message("note_off", channel=0, note=k, velocity=64)))
        events.sort(key=lambda e: (e[0], e[1]))
        track, prev = mido.MidiTrack(), 0
        track.append(mido.MetaMessage("track_name", name="Melody", time=0))
        track.append(mido.Message("program_change", channel=0, program=73, time=0))
        for at, _, msg in events:
            track.append(msg.copy(time=at - prev))
            prev = at
        track.append(mido.MetaMessage("end_of_track", time=0))
        mf.tracks.append(track)
        cond.append(mido.MetaMessage("end_of_track", time=prev))
        fname = f"sc4-perf-{index + 1:02d}.mid"
        mf.save(os.path.join(HERE, fname))
        result, E, choices, beats = import_performance(rendered, meter, prev)
        truth_onsets = {t[0] for t in truth}
        wrong = [r for r in result if r[0] not in truth_onsets]
        flagged = [r for r in result if r[3] < F(4, 5)]
        unflagged_wrong = [r for r in wrong if r[3] >= F(4, 5)]
        rows.append([fname, name, title, meter, key, bpm, pad, E,
                     [[a, z, p, midi_of(p)] for a, z, p in truth],
                     [[a, z, k, q] for a, z, k, q in result],
                     len(wrong), len(flagged), len(unflagged_wrong)])
    return rows


# --- import fixtures --------------------------------------------------------


def write_mid(name, tracks, division=480, fmt=1):
    """TRACKS: lists of (tick, mido message); each sorted stably by tick."""
    import mido
    mf = mido.MidiFile(type=fmt, ticks_per_beat=division)
    for events in tracks:
        track, prev = mido.MidiTrack(), 0
        evs = sorted(events, key=lambda e: e[0])
        for at, msg in evs:
            track.append(msg.copy(time=at - prev))
            prev = at
        track.append(mido.MetaMessage("end_of_track", time=0))
        mf.tracks.append(track)
    mf.save(os.path.join(HERE, name))


def notes_events(notes, channel, division=480):
    """(start end pitch-name) in whole notes -> timed note messages."""
    import mido
    out = []
    for a, z, p in notes:
        out.append((tick(z, division), mido.Message("note_off", channel=channel, note=midi_of(p), velocity=0)))
        out.append((tick(a, division), mido.Message("note_on", channel=channel, note=midi_of(p), velocity=80)))
    out.sort(key=lambda e: (e[0], 0 if e[1].type == "note_off" else 1))
    return out


def seq_notes(start, text):
    out, pos = [], start
    for pitch, dur in melody_notes(text):
        if pitch != "r":
            out.append((pos, pos + dur, pitch))
        pos += dur
    return out


def meta(kind, **kw):
    import mido
    return mido.MetaMessage(kind, **kw)


def kk_rank(keys):
    """MT4 DETECT-KEY over a :COUNT histogram of KEYS, Krumhansl-Kessler."""
    major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    hist = [0] * 12
    for k in keys:
        hist[k % 12] += 1
    names_major = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    names_minor = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B"]
    out = []
    for t in range(12):
        for mode, prof, names in (("major", major, names_major), ("minor", minor, names_minor)):
            p = [prof[(i - t) % 12] for i in range(12)]
            pm, hm = sum(p) / 12, sum(hist) / 12
            cov = sum((p[i] - pm) * (hist[i] - hm) for i in range(12))
            r = cov / math.sqrt(sum((x - pm) ** 2 for x in p) * sum((x - hm) ** 2 for x in hist))
            out.append((r, f"{names[t]} {mode}"))
    order = sorted(range(24), key=lambda i: -out[i][0])
    return [out[i] for i in order]


def music21_key(keys):
    from music21 import stream, note
    from music21.analysis import discrete
    s = stream.Stream()
    for k in keys:
        s.append(note.Note(k, quarterLength=1))
    analysis = discrete.KrumhanslKessler(s)
    k = analysis.getSolution(s)
    return k.tonic.pitchClass, k.mode, k.correlationCoefficient


def import_fixtures():
    import mido
    facts = []
    # Ensemble: piano chords, flute melody, bass line, drums; lyrics on a
    # notes-less track go to the melody.
    piano = [(F(0), F(1, 2), "F3"), (F(0), F(1, 2), "A3"), (F(0), F(1, 2), "C4"),
             (F(1, 2), F(1), "G3"), (F(1, 2), F(1), "Bb3"), (F(1, 2), F(1), "C4"),
             (F(1), F(2), "F3"), (F(1), F(2), "A3"), (F(1), F(3, 2), "C4"),
             (F(3, 2), F(2), "D4")]
    flute = seq_notes(F(0), "C5:1/4 A4:1/4 F4:1/4 A4:1/4 G4:1/2 Bb4:1/2 A4:1/4 C5:1/4 F5:1/2")
    bass = seq_notes(F(0), "F2:1/2 C3:1/2 F2:1")
    drums = [(F(i, 4), F(i, 4) + F(1, 8), "C2") for i in range(8)]
    words = [(F(0), "Here-"), (F(1, 4), "we"), (F(1, 2), "go")]
    cond = [(0, meta("track_name", name="Ensemble")), (0, meta("set_tempo", tempo=600000)),
            (0, meta("time_signature", numerator=4, denominator=4, clocks_per_click=24,
                     notated_32nd_notes_per_beat=8)),
            (0, meta("key_signature", key="F"))]
    t_piano = [(0, meta("track_name", name="Piano")), (0, meta("instrument_name", name="Piano"))] + notes_events(piano, 0)
    t_flute = [(0, meta("track_name", name="Flute"))] + notes_events(flute, 1)
    t_bass = [(0, meta("track_name", name="Bass"))] + notes_events(bass, 2)
    t_drums = [(0, meta("track_name", name="Drums"))] + notes_events(drums, 9)
    t_words = [(0, meta("track_name", name="Words"))] + [(tick(a, 480), meta("lyrics", text=x)) for a, x in words]
    write_mid("sc4-ensemble.mid", [cond, t_piano, t_flute, t_bass, t_drums, t_words])
    merged = cond + t_piano + t_flute + t_bass + t_drums + t_words
    write_mid("sc4-ensemble-format0.mid", [merged], fmt=0)
    facts.append(["sc4-ensemble.mid", Kw("piano"), [[a, z, midi_of(p)] for a, z, p in piano],
                  Kw("flute"), [[a, z, midi_of(p)] for a, z, p in flute],
                  Kw("bass"), [[a, z, midi_of(p)] for a, z, p in bass]])
    # Strings: instrument names group tracks into parts.
    strings = [("Violin I", "Violins", "A4:1/2 B4:1/2 C5:1"), ("Violin II", "Violins", "F4:1/2 G4:1/2 A4:1"),
               ("Viola", "Viola", "C4:1 F4:1"), ("Cello", None, "F2:1 F3:1")]
    tracks = [[(0, meta("set_tempo", tempo=500000)),
               (0, meta("time_signature", numerator=4, denominator=4, clocks_per_click=24,
                        notated_32nd_notes_per_beat=8))]]
    for ch, (name, inst, text) in enumerate(strings):
        tr = [(0, meta("track_name", name=name))]
        if inst:
            tr.append((0, meta("instrument_name", name=inst)))
        tracks.append(tr + notes_events(seq_notes(F(0), text), ch))
    write_mid("sc4-strings.mid", tracks)
    # Lyrics: hyphenation, an early lyric, control characters, a collision.
    melody = seq_notes(F(0), "D4:1/4 G4:1/2 B4:1/8 G4:1/8 B4:1/2 A4:1/4 G4:3/4")
    lyr = [(F(0), "A-"), (F(1, 4) - F(1, 96), "maz-"), (F(3, 4), "ing"), (F(7, 8), " grace\r"),
           (F(1), "how"), (F(1), "sweet"), (F(3, 2), "the")]
    tr = [(0, meta("track_name", name="Voice"))] + notes_events(melody, 0) + \
        [(tick(a, 480), meta("lyrics", text=x)) for a, x in lyr]
    write_mid("sc4-lyrics.mid", [[(0, meta("time_signature", numerator=3, denominator=4,
                                           clocks_per_click=24, notated_32nd_notes_per_beat=8)),
                                  (0, meta("key_signature", key="G"))], tr])
    # Karaoke: text events, "@" headers, breaks, word boundaries by spaces.
    tw = seq_notes(F(0), "C4:1/4 C4:1/4 G4:1/4 G4:1/4 A4:1/4 A4:1/4 G4:1/2 F4:1/4 F4:1/4 E4:1/4 E4:1/4 D4:1/4 D4:1/4 C4:1/2")
    syll = ["\\Twin", "kle ", "twin", "kle ", "lit", "tle ", "star,", "/How ", "I ", "won", "der ",
            "what ", "you ", "are"]
    words = [(0, meta("text", text="@KMIDI KARAOKE FILE")), (0, meta("text", text="@LENGL")),
             (0, meta("text", text="@TTwinkle, Twinkle"))]
    words += [(tick(a, 480), meta("text", text=s)) for (a, _, _), s in zip(tw, syll)]
    write_mid("sc4-karaoke.mid", [[(0, meta("time_signature", numerator=4, denominator=4,
                                            clocks_per_click=24, notated_32nd_notes_per_beat=8))],
                                  [(0, meta("track_name", name="Words"))] + words,
                                  [(0, meta("track_name", name="Melody"))] + notes_events(tw, 0)])
    # Meta: pickup, key and meter changes, tempo inside a bar, markers, chord
    # text with and without the prefix, a short final bar.
    q = lambda x: tick(x, 480)
    cond = [(0, meta("track_name", name="Meta Test")), (0, meta("copyright", text="(c) Nobody")),
            (0, meta("time_signature", numerator=1, denominator=4, clocks_per_click=24,
                     notated_32nd_notes_per_beat=8)),
            (0, meta("key_signature", key="D")), (0, meta("set_tempo", tempo=666667)),
            (q(F(1, 4)), meta("time_signature", numerator=3, denominator=4, clocks_per_click=24,
                              notated_32nd_notes_per_beat=8)),
            (q(F(1, 4)), meta("marker", text="A")), (q(F(1, 4)), meta("text", text="chord:D")),
            (q(F(1, 2)), meta("text", text="G")), (q(F(3, 4)), meta("text", text="Intro")),
            (q(F(1)), meta("marker", text="chord:A7")),
            (q(F(7, 4)), meta("key_signature", key="Dm")),
            (q(F(5, 2)), meta("time_signature", numerator=6, denominator=8, clocks_per_click=36,
                              notated_32nd_notes_per_beat=8)),
            (q(F(5, 2)), meta("marker", text="B")),
            (q(F(5, 2) + F(1, 8)), meta("set_tempo", tempo=1000000)),
            (q(F(13, 4)), meta("time_signature", numerator=3, denominator=8, clocks_per_click=12,
                               notated_32nd_notes_per_beat=8))]
    mel = seq_notes(F(0), "A4:1/4 D5:1/2 C#5:1/4 B4:1/2 A4:1/4 F4:3/4 A4:3/8 G4:3/8 F4:3/8")
    write_mid("sc4-meta.mid", [cond, [(0, meta("track_name", name="Tune"))] + notes_events(mel, 0)])
    facts.append(["sc4-meta.mid", Kw("melody"), [[a, z, midi_of(p)] for a, z, p in mel]])
    # Spelling: diatonic melodies in C# major and Gb major, no key or time
    # signature; and one G#4 in C major, which MT4 can't decide.
    for fname, key, text in (("sc4-spell-c-sharp.mid", "C# major",
                              "C#4:1/4 E#4:1/4 G#4:1/4 C#5:1/4 B#4:1/4 A#4:1/4 G#4:1/4 F#4:1/4 "
                              "E#4:1/4 D#4:1/4 C#4:1/4 G#4:1/4 C#4:1/4 E#4:1/4 G#4:1/4 C#4:1/4"),
                             ("sc4-spell-g-flat.mid", "Gb major",
                              "Gb4:1/4 Bb4:1/4 Db5:1/4 Gb5:1/4 F5:1/4 Eb5:1/4 Db5:1/4 Cb5:1/4 "
                              "Bb4:1/4 Ab4:1/4 Gb4:1/4 Db5:1/4 Gb4:1/4 Bb4:1/4 Db5:1/4 Gb4:1/4")):
        notes = seq_notes(F(0), text)
        head = ([(0, meta("time_signature", numerator=4, denominator=4, clocks_per_click=24,
                          notated_32nd_notes_per_beat=8))] if "sharp" in fname else [])
        write_mid(fname, [head + [(0, meta("track_name", name="Melody"))] + notes_events(notes, 0)])
        keys = [midi_of(p) for _, _, p in notes]
        ranking = kk_rank(keys)
        pc, mode, r21 = music21_key(keys)
        best_r, best = ranking[0]
        if abs(best_r - r21) > 1e-9 or best.split()[1] != mode:
            raise SystemExit(f"{fname}: music21 says {pc} {mode} {r21}, the rules {best} {best_r}")
        if ranking[0][0] - ranking[1][0] < 0.05:
            raise SystemExit(f"{fname}: key detection too close {ranking[:2]}")
        facts.append([fname, key, best, best_r, [[a, z, p, midi_of(p)] for a, z, p in notes]])
    write_mid("sc4-spell-ambiguous.mid",
              [[(0, meta("time_signature", numerator=4, denominator=4, clocks_per_click=24,
                         notated_32nd_notes_per_beat=8)), (0, meta("key_signature", key="C"))],
               [(0, meta("track_name", name="Line"))] + notes_events([(F(0), F(1), "G#4")], 0)])
    mel = seq_notes(F(0), "G4:1/4 B4:1/4 D5:1/4 B4:1/4 C5:1/4 A4:1/4 F#4:1/4 G4:1/4")
    write_mid("sc4-key-mismatch.mid",
              [[(0, meta("time_signature", numerator=4, denominator=4, clocks_per_click=24,
                         notated_32nd_notes_per_beat=8)), (0, meta("key_signature", key="G")),
                (0, meta("set_tempo", tempo=500000))],
               [(0, meta("track_name", name="Line"))] + notes_events(mel, 0)])
    facts.append(["sc4-key-mismatch.mid", [[a, z, p, midi_of(p)] for a, z, p in mel]])
    write_form("sc4-import-facts.sexp",
               "SC4 import fixtures: the notes each .mid holds (whole notes, MIDI keys).", facts)


# --- 0.1.1 import fixtures (sc41-*) ------------------------------------------
# The performance of issue #4: the "Ode to Joy" theme (Beethoven, 1824), bars
# 1-4 and 9-12 in D major, bar 7 varied with a triplet F#4 G4 G#4 rising to A4,
# played at quarter = 100 with onsets up to 20 ms off, notes held for 90%, from
# a seeded linear congruential generator; format 0 with a tempo and a program
# change, no time or key signature. And a file whose last note starts so late
# that it snaps to the end of the last bar (issue #3, item 1).

ODE = ["F#4 F#4 G4 A4", "A4 G4 F#4 E4", "D4 D4 E4 F#4", "F#4/3:8 E4/1:8 E4/2",
       "E4 E4 F#4 D4", "E4 F#4/1:8 G4/1:8 F#4 D4", "E4 F#4/1:12 G4/1:12 G#4/1:12 A4 F#4",
       "D4 E4 A3/2"]


def ode_notes():
    """((onset duration pitch) ...): a pitch, then /n:d for n/d of a whole note,
    /n for 1/n, else a quarter."""
    out, onset = [], F(0)
    for bar in ODE:
        for token in bar.split():
            pitch, _, dur = token.partition("/")
            if not dur:
                d = F(1, 4)
            elif ":" in dur:
                n, den = dur.split(":")
                d = F(int(n), int(den))
            else:
                d = F(1, int(dur))
            out.append((onset, d, pitch))
            onset += d
    return out


def ode_performance():
    """((onset duration pitch on off velocity jitter) ...): x <- (1103515245 x +
    12345) mod 2^31 from 1824; per note the jitter (x >> 8) mod 41 - 20 ms (its
    absolute value on the first note), then the velocity 70 + (x >> 8) mod 21;
    600 ms per quarter, 480 ticks per quarter, both rounded half to even."""
    x = 1824
    rows = []
    for onset, d, pitch in ode_notes():
        x = (1103515245 * x + 12345) % 2 ** 31
        jitter = ((x >> 8) % 41) - 20
        if onset == 0:
            jitter = abs(jitter)
        ms = onset * 4 * 600 + jitter
        on = round(ms * 480 / F(600))
        off = on + round(F(9, 10) * d * 4 * 480)
        x = (1103515245 * x + 12345) % 2 ** 31
        rows.append((onset, d, pitch, on, off, 70 + ((x >> 8) % 21), jitter))
    return rows


def sc41_fixtures():
    import mido
    facts = []
    rows = ode_performance()
    jitters = [r[6] for r in rows]
    if jitters[:4] != [17, 5, -7, -17] or jitters[-9:] != [7, -9, -5, 10, 2, 19, -10, 9, 4]:
        raise SystemExit(f"sc41-perf-ode.mid: the generator drifted: {jitters}")
    events = [(0, meta("set_tempo", tempo=600000)),
              (0, mido.Message("program_change", channel=0, program=0))]
    for _, _, pitch, on, off, vel, _ in rows:
        events.append((on, mido.Message("note_on", channel=0, note=midi_of(pitch), velocity=vel)))
        events.append((off, mido.Message("note_off", channel=0, note=midi_of(pitch), velocity=64)))
    write_mid("sc41-perf-ode.mid", [events], fmt=0)
    rendered = [[on, off, midi_of(pitch), vel] for _, _, pitch, on, off, vel, _ in rows]
    result, E, _, _ = import_performance(rendered, "4/4", max(r[4] for r in rows))
    if [r[0] for r in result] != [r[0] for r in rows]:
        raise SystemExit("sc41-perf-ode.mid: an onset doesn't snap to its written position")
    facts.append(["sc41-perf-ode.mid", Kw("end"), E,
                  Kw("truth"), [[a, a + d, p, midi_of(p)] for a, d, p, *_ in rows],
                  Kw("import"), [[a, z, k, q] for a, z, k, q in result]])
    # The late last note: F4, written on beat 4, played 0.92 of a beat late and
    # short, ends before the barline; its start snaps to the end of the bar.
    late = [(0, 400, "C4", "one"), (480, 880, "D4", "two"), (960, 1360, "E4", "three"),
            (1882, 1910, "F4", "four")]
    melody = [(0, meta("track_name", name="Line"))]
    for on, off, pitch, text in late:
        melody += [(on, mido.Message("note_on", channel=0, note=midi_of(pitch), velocity=80)),
                   (on, meta("lyrics", text=text)),
                   (off, mido.Message("note_off", channel=0, note=midi_of(pitch), velocity=0))]
    write_mid("sc41-late-last-note.mid",
              [[(0, meta("time_signature", numerator=4, denominator=4, clocks_per_click=24,
                         notated_32nd_notes_per_beat=8)), (0, meta("key_signature", key="C"))],
               melody])
    result, E, choices, beats = import_performance([[on, off, midi_of(p), 80] for on, off, p, _ in late],
                                                   "4/4", 1910)
    _, positions, _ = quantize(sorted({F(on, 1920) for on, *_ in late}), beats)
    if positions[-1] != E or result[-1][0] != F(3, 4):
        raise SystemExit("sc41-late-last-note.mid: the last start doesn't snap to the end")
    facts.append(["sc41-late-last-note.mid", Kw("end"), E,
                  Kw("notes"), [[on, off, midi_of(p), text] for on, off, p, text in late],
                  Kw("import"), [[a, z, k, q] for a, z, k, q in result]])
    write_form("sc41-facts.sexp",
               "0.1.1 import fixtures: (file :end E :truth ((start end pitch key) ...) or :notes "
               "((on-tick off-tick key lyric) ...), :import ((start end key q) ...)), q the "
               "quantisation confidence the rules give each note.", facts)


# --- main ------------------------------------------------------------------

EXPORT_FIXTURES = ["sc0-carol-6-8", "sc0-chords-under-rests", "sc0-jumps", "sc0-key-change",
                   "sc0-keyboard", "sc0-omr-result", "sc0-pickup", "sc0-repeats-voltas",
                   "sc0-satb", "sc0-three-verses", "sc4-dynamics", "sc4-rhythms", "sc4-strophic"]

VARIANTS = [
    ("satb-part-layout", "sc0-satb", {"layout": "part"}, [Kw("layout"), Kw("part")]),
    ("voltas-as-written", "sc0-repeats-voltas", {"unfold": None}, [Kw("unfold"), None]),
    ("three-verses-verse-2", "sc0-three-verses", {"verse": 2}, [Kw("verse"), 2]),
    ("three-verses-no-lyrics", "sc0-three-verses", {"verse": None}, [Kw("verse"), None]),
    ("strophic-verse-per-pass", "sc4-strophic", {"verse": "pass"}, [Kw("verse"), Kw("pass")]),
    ("chords-as-markers", "sc0-chords-under-rests", {"chord_symbols": "marker"},
     [Kw("chord-symbols"), Kw("marker")]),
    ("chords-dropped", "sc0-chords-under-rests", {"chord_symbols": None}, [Kw("chord-symbols"), None]),
    ("keyboard-division-96", "sc0-keyboard", {"division": 96}, [Kw("division"), 96]),
    ("keyboard-division-100", "sc0-keyboard", {"division": 100}, [Kw("division"), 100]),
    ("keyboard-programs", "sc0-keyboard", {"program": 0, "programs": {"p-5": 73, "v-1h": 32}},
     [Kw("program"), 0, Kw("programs"), [Cons("p-5", 73), Cons("v-1h", 32)]]),
    ("dynamics-forte-default", "sc4-dynamics", {"default_dynamic": "f"}, [Kw("default-dynamic"), Kw("f")]),
    ("satb-mix", "sc0-satb", {"mix": {"v-s": {"velocity": 20, "volume": 127, "pan": 64},
                                      "p-5": {"volume": 70, "pan": 20}}},
     [Kw("mix"), [Cons("v-s", [Kw("velocity"), 20, Kw("volume"), 127, Kw("pan"), 64]),
                  Cons("p-5", [Kw("volume"), 70, Kw("pan"), 20])]]),
    ("jumps-custom-order", "sc0-jumps", {"unfold": [(1, 1), (2, 1), (2, 2), (7, 1)]},
     [Kw("unfold"), [1, 2, Cons(2, 2), 7]]),
    ("carol-dynamics-p", "sc0-carol-6-8", {"default_dynamic": "p", "chord_symbols": None},
     [Kw("default-dynamic"), Kw("p"), Kw("chord-symbols"), None]),
]

def dump():
    import mido
    data = sys.stdin.buffer.read()
    out, pos = [], 0
    while pos < len(data):
        length = 14
        ntrks = int.from_bytes(data[pos + 10:pos + 12], "big")
        p = pos + 14
        for _ in range(ntrks):
            p += 8 + int.from_bytes(data[p + 4:p + 8], "big")
        mf = mido.MidiFile(file=io.BytesIO(data[pos:p]))
        tracks = []
        for tr in mf.tracks:
            at, name, evs = 0, "", []
            for msg in tr:
                at += msg.time
                if msg.type == "track_name" and not name:
                    name = msg.name
                if msg.type in ("note_on", "note_off"):
                    evs.append([at, Kw(msg.type.replace("_", "-")), msg.channel, msg.note, msg.velocity])
                elif msg.type == "lyrics":
                    evs.append([at, Kw("lyric"), msg.text])
                elif msg.type == "set_tempo":
                    evs.append([at, Kw("tempo"), msg.tempo])
            tracks.append([name, evs])
        out.append([mf.type, mf.ticks_per_beat, tracks])
        pos = p
    sys.stdout.write(lisp(out) + "\n")


def main():
    if "--dump" in sys.argv:
        dump()
        return
    renumber = "--renumber" in sys.argv
    scores = {}
    for name in EXPORT_FIXTURES:
        path = os.path.join(HERE, name + ".sexp")
        with open(path, encoding="utf-8") as f:
            text = f.read()
        canonical = renumbered(text)
        if canonical != text:
            if not renumber or name.startswith("sc0-"):
                sys.exit(f"{name}: ids are not in document order (run with --renumber)")
            with open(path, "w", encoding="utf-8") as f:
                f.write(canonical)
        scores[name] = Score(name, canonical)
    facts_rows = []
    for name in EXPORT_FIXTURES:
        score = scores[name]
        tracks, end_tick, facts = export(score)
        check_with_music21(score, facts, 480)
        with open(os.path.join(HERE, f"sc4-export-{name[4:]}.mid"), "wb") as out:
            out.write(smf_bytes(tracks, end_tick, 480))
        mm = import_measure_map(facts["time-signatures"], facts["key-signatures"], facts["tempos"],
                                facts["markers"], end_tick, 480)
        facts_rows.append([name, Kw("end"), end_tick,
                           Kw("bars"), facts["bars"],
                           Kw("time-signatures"), facts["time-signatures"],
                           Kw("key-signatures"), facts["key-signatures"],
                           Kw("tempos"), facts["tempos"],
                           Kw("markers"), facts["markers"],
                           Kw("chords"), facts["chords"],
                           Kw("losses"), facts["losses"],
                           Kw("voices"), [[vf["id"], vf["label"], vf["part"], vf["channel"], vf["program"],
                                           vf["notes"], vf["lyrics"], vf["spellings"]]
                                          for vf in facts["voices"]],
                           Kw("measures"), mm])
    write_form("sc4-export-facts.sexp",
               "SC4 SCORE-TO-SMF of every fixture score with default options: played bars "
               "(bar pass start-tick), meta events (tick ...), voices (id track-name part-label "
               "channel program notes ((on off key velocity)...) lyrics ((tick text syllabic)...) spellings "
               "((on key pitch in-key)...)), and the measure map the import rebuilds "
               "((length time key pickup tempo-marks rehearsal)...).", facts_rows)
    variant_rows = []
    for vname, fixture, opts, form in VARIANTS:
        unfold = opts.get("unfold", True)
        kw = dict(opts)
        tracks, end_tick, facts = export(scores[fixture], **kw)
        division = opts.get("division", 480)
        with open(os.path.join(HERE, f"sc4-variant-{vname}.mid"), "wb") as out:
            out.write(smf_bytes(tracks, end_tick, division))
        variant_rows.append([vname, fixture, form, facts["losses"]])
    write_form("sc4-variants.sexp",
               "SC4 SCORE-TO-SMF option rows: (name fixture options losses); the bytes are "
               "sc4-variant-<name>.mid.", variant_rows)
    write_form("sc4-quantize.sexp",
               "SC4 QUANTIZE-ONSETS rows: (label beats onsets subdivisions exact choices positions "
               "confidences), by brute force over every allowed grid.", quantize_rows())
    perf = performance_rows()
    write_form("sc4-performances.sexp",
               "SC4 performances: (file name title meter key bpm padding end truth ((start end "
               "pitch key)...) import ((start end key confidence)...) wrong flagged "
               "wrong-unflagged).", perf)
    for row in perf:
        print(f"{row[0]} {row[1]}: {len(row[9])} notes, {row[10]} wrong, {row[11]} flagged, "
              f"{row[12]} wrong but unflagged")
    import_fixtures()
    sc41_fixtures()


if __name__ == "__main__":
    main()
