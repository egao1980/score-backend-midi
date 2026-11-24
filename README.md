# score-backend-midi

Standard MIDI File export and import for [score-protocol](https://github.com/egao1980/score-protocol), on [midi-protocol](https://github.com/egao1980/midi-protocol).

- **Export** (`score-to-smf`, `export-midi`): SMF type 1 with a conductor track (tempo map, time and key signatures, rehearsal markers, chord symbols as `chord:`-prefixed text or marker events) and one track per voice or per part, one channel per voice. Repeats, endings and jumps are played in the order of score-protocol's `unfold` view, ties sound as one note, dynamics set velocities, lyrics are `FF 05` events, and a per-voice mix sets velocity, volume (CC7) and pan. `rehearsal-set` writes one practice file per voice with that voice brought forward.
- **Import** (`smf-to-score`, `import-midi`): tracks and channels become parts and voices (or just the melody, the highest monophonic line), meta events build the measure map, onsets are quantised to a grid chosen per beat (straight or triplet) through `sat-protocol:minimize`, pitches are spelled with [music-theory](https://github.com/egao1980/music-theory), lyrics and karaoke text become lyrics, and every guess (quantisation, spelling, key, meter, chord symbol, lyric placement, melody choice) is recorded in the elements' provenance and confidence, so `score-protocol:uncertain-elements` is the uncertainty report.

**Status:** SC4 contract (0.1.0). The rules are in the file headers under `src/`, the Rove suite under `tests/` is the spec, and the functions are stubs. The design is in the capability brief [cl-stack/docs/capabilities/score.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/score.md), slice SC4. Fixtures and oracles (music21 for what sounds when, mido for the bytes): [tests/fixtures/PROVENANCE.md](tests/fixtures/PROVENANCE.md).

Spelling and key detection come from music-theory 0.5.0 (slice MT4), pinned here. The tests system pins rove 0.11.1, whose `deftest-parametrize :rows` binds row values as data.

```sh
cl-repo test --system score-backend-midi
```

## License

MIT, see [LICENSE](LICENSE).
