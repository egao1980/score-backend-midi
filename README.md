# score-backend-midi

Standard MIDI File export and import for [score-protocol](https://github.com/egao1980/score-protocol), on [midi-protocol](https://github.com/egao1980/midi-protocol).

- **Export** (`score-to-smf`, `export-midi`): SMF type 1 with a conductor track (tempo map, time and key signatures, rehearsal markers, chord symbols as `chord:`-prefixed text or marker events) and one track per voice or per part, one channel per voice. Repeats, endings and jumps are played in the order of score-protocol's `unfold` view, ties sound as one note, dynamics set velocities, lyrics are `FF 05` events, and a per-voice mix sets velocity, volume (CC7) and pan. `rehearsal-set` writes one practice file per voice with that voice brought forward.
- **Import** (`smf-to-score`, `import-midi`): tracks and channels become parts and voices (or just the melody, the highest monophonic line), meta events build the measure map, onsets are quantised to a grid chosen per beat (straight or triplet) through `sat-protocol:minimize`, pitches are spelled with [music-theory](https://github.com/egao1980/music-theory), lyrics and karaoke text become lyrics, and every guess (quantisation, spelling, key, meter, chord symbol, lyric placement, melody choice) is recorded in the elements' provenance and confidence, so `score-protocol:uncertain-elements` is the uncertainty report.
- **Timed notes** (`notes-to-score`, `estimate-tempo`; 0.2.0, **contract**): one melodic line of note events that come from no SMF, as a monophonic transcriber of a recorded melody gives them (onset and offset in seconds, a MIDI pitch with cents, a confidence), becomes a one-voice score by the import's own quantisation and spelling. Key and tuning are fitted together with music-theory's `fit-key`, the tempo is estimated from the onsets (or given), and the grid, origin and tempo are fitted together; every guess (tempo, meter, downbeat, key, onsets, pitches, the source's own doubts) is flagged, and the second value, a `notes-fit`, holds the numbers behind them (the key hint's distance, each note's deviation in cents).

| Slice | Version | State |
|-------|---------|-------|
| SC4: export and import | 0.1.0 | implemented |
| 0.1.1: spelling confidence (#4), late last note (#3) | 0.1.1 | implemented |
| SC6: timed notes to a score (#7) | 0.2.0 | **contract**: `notes-to-score` and `estimate-tempo` are stubs; the rules are in `src/notes.lisp` and `src/tempo.lisp`, the tests in `tests/notes-test.lisp` and `tests/tempo-test.lisp` |

**Status:** 0.1.1 implemented; 0.2.0 (SC6) is a contract. 0.1.1 amends two import rules of 0.1.0 (SC4): a spelling's confidence now follows the music-theory rule that decided it, so a chromatic note a rule settles is no longer flagged (#4), and a start snapped to the end of the last bar moves back into it, flagged (#3). The rules are in the file headers under `src/`, the Rove suite under `tests/` is the spec. The design is in the capability brief [cl-stack/docs/capabilities/score.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/score.md), slices SC4 and SC6. 0.2.0 moved the import's quantisation, spelling and building into functions `notes-to-score` shares, without changing what `smf-to-score` does (its tests pin it). Fixtures and oracles (music21 for what sounds when, mido for the bytes): [tests/fixtures/PROVENANCE.md](tests/fixtures/PROVENANCE.md).

Spelling and key detection come from music-theory (slice MT4), pinned at 0.6.0: the 0.5.1 chromatic spelling (music-theory#14), the rule that decided each note as SPELL-SEQUENCE's third value (music-theory#19), and MT5's `fit-key`, a key and tuning offset fitted together (music-theory#22). score-protocol is pinned at 0.3.0 for the direction of `lossy-conversion`. The tests system pins rove 0.11.1, whose `deftest-parametrize :rows` binds row values as data.

```sh
cl-repo test --system score-backend-midi
```

## License

MIT, see [LICENSE](LICENSE).
