# Test fixture provenance

Regenerate rather than hand-edit. Everything below except the copied SC0 scores is written by `generate-sc4.py`:

```sh
uv run --no-project --with music21==10.5.2 --with mido==1.3.3 python -I tests/fixtures/generate-sc4.py
```

The script is a second implementation of the rules in `src/*.lisp`, in Python, written from the file headers and independent of the Lisp code. For the musical facts it defers to [music21](https://github.com/cuthbertLab/music21) 10.5.2 (BSD-3-Clause): every fixture score is also built in music21, expanded with `expandRepeats` and `stripTies`, and the script stops when music21's notes (onset, end, key), its bar order or its tempi differ from its own. Every `.mid` file is written by [mido](https://github.com/mido/mido) 1.3.3 (MIT), so the bytes are mido's encoding of the events the rules call for. Both run out of process; neither is a dependency of the library.

| File | Source | SPDX | How |
|------|--------|------|-----|
| `sc0-*.sexp` (10 scores) | copied unchanged from score-protocol `tests/fixtures` at `f766345` (SC0); hand-built, the tunes and texts named in each header are public domain | MIT | copy |
| `sc4-dynamics.sexp`, `sc4-rhythms.sexp` | hand-built for these tests | MIT | written in score-protocol's canonical form; ids by `generate-sc4.py --renumber` |
| `sc4-strophic.sexp` | hand-built; text after Isaac Watts, *Joy to the World* (1719, public domain) | MIT | same |
| `sc4-export-*.mid` | `SCORE-TO-SMF` of each fixture score with default options | MIT (generated) | the script's export rules, checked against music21, written with mido |
| `sc4-export-facts.sexp` | the same exports as readable rows: played bars, meta events, per-voice notes, lyrics, spellings, losses, and the measure map the import rebuilds | MIT (generated) | same |
| `sc4-variant-*.mid`, `sc4-variants.sexp` | `SCORE-TO-SMF` with the options of each row (layout, unfold, verse, chord symbols, division, programs, mix, default dynamic) | MIT (generated) | same |
| `sc4-quantize.sexp` | `QUANTIZE-ONSETS` of 12 hand cases (straight, triplet, swing, dotted, compound, duplet, cut and pickup beats), 11 of them exact, 2 with other subdivision lists, and 40 seeded random cases | MIT (generated) | brute force over every allowed grid |
| `sc4-perf-01.mid` … `sc4-perf-10.mid` | humanised renderings of ten melodies (below) | MIT (generated) | seeded timing errors, written with mido |
| `sc4-performances.sexp` | for each rendering: the notation (the truth) and the import the rules give | MIT (generated) | the script's quantisation and import rules |
| `sc4-ensemble.mid`, `sc4-ensemble-format0.mid`, `sc4-strings.mid`, `sc4-lyrics.mid`, `sc4-karaoke.mid`, `sc4-meta.mid`, `sc4-spell-c-sharp.mid`, `sc4-spell-g-flat.mid`, `sc4-spell-ambiguous.mid`, `sc4-key-mismatch.mid` | import cases designed for these tests: tracks and channels, instrument names, percussion, lyric and karaoke conventions, meta events and hints, spelling with and without a key | MIT (generated) | written with mido; notes in `sc4-import-facts.sexp` |
| `sc4-import-facts.sexp` | the notes of those files, and for the spelling files the key music21 detects | MIT (generated) | the script; music21 `KrumhanslKessler` |

## The performances

The brief asks for "unquantised human performances of corpus melodies (recorded, MIT)". Recordings made for this repository don't exist yet, so these are **synthetic**: each melody, re-encoded by us from a public-domain tune (one, *Triplet Study*, written for these tests), is placed after the rests that put its pickup on the right beat, then every onset is moved by a seeded gaussian error (σ from 2% to 7% of a quarter note; performances 5 and 10 are the sloppy ones), every note is held for 60-100% of its value, and velocities vary. A click track is assumed: ticks follow the beat. Each file has a conductor track with the tempo, the time signature and the key signature of the melody, and the melody in a second track. Replacing them with real recordings keeps the tests as they are once `sc4-performances.sexp` is regenerated from the new files' truth.

| # | Melody | Source |
|---|--------|--------|
| 1 | Amazing Grace | tune 1829 |
| 2 | Old Hundredth | Genevan Psalter, 1551 |
| 3 | Ah! vous dirai-je, maman | 18th century |
| 4 | Ode to Joy | Beethoven, 1824 |
| 5 | Frère Jacques | traditional |
| 6 | Stille Nacht | Gruber, 1818 |
| 7 | Row, Row, Row Your Boat | 1852 |
| 8 | Minuet in G | Petzold, c. 1725 |
| 9 | Triplet Study | written for these tests |
| 10 | Jingle Bells | Pierpont, 1857 |

The grid weights of `+GRID-WEIGHTS+` (`:level 50`, `:tuplet 30`) and the margin term of the confidence were set on renderings like these (8 seeds × 10 melodies, σ scaled 0.7× to 2.5×): with them every misplaced onset of the ten committed renderings is flagged, and 246 of 254 onsets land where the notation has them.

## Where the rules differ from music21

The export plays score-protocol's `UNFOLD` view (SC1, 0.2.0). To derive the facts, the script walks the same rules in Python; music21's `expandRepeats` agrees with that walk on both fixture scores with navigation ("Repeats and Voltas", "Dal Segno al Coda"), and `export-plays-unfold` checks the walk against the real `UNFOLD`, passes included. Where music21 and `UNFOLD` part ways on other scores (no forward repeat, endings after a jump, malformed navigation) is score-protocol's PROVENANCE. One consequence for lyrics: a bar's PASS counts how many times it has been played, so a second ending played once is pass 1 and `:VERSE :PASS` gives it verse 1 (the strophic fixture shows it).

- **Ties between chord notes.** music21's `stripTies` doesn't join a tie between single notes of two chords; the script joins those segments before comparing (the tied G4 of the SC0 keyboard fixture).
- **Velocity.** Ours is the `+DYNAMIC-VELOCITIES+` table along the playback order. music21's realised volume saturates at ff (ff and fff both give 127), so velocities are checked against the table and by hand, not against music21.
- **Time signatures of short bars.** A pickup or a short last bar is written with a signature of its actual length (1/4 before 3/4); music21 writes the notated meter. This is what lets the import rebuild the pickup.
- **Units.** Offsets are whole notes; music21's are quarter notes; ticks are quarter-note based (480 per quarter by default).

## Key detection

The spelling files have no key signature. The script ranks the 24 keys of MT4's candidate list with the Krumhansl-Kessler profiles over a count histogram (MT4 `PITCH-CLASS-HISTOGRAM :WEIGHT :COUNT`, `DETECT-KEY`), and stops unless music21's `KrumhanslKessler` analysis finds the same correlation and mode, and the winner leads by at least 0.05. The C# major melody detects as Db major and the Gb major melody as F# major (both r = 0.9613), the spellings MT4 gives those pitch classes, so a key hint turns every spelling from wrong to right.
