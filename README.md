# score-backend-midi

Standard MIDI File export and import for [score-protocol](https://github.com/egao1980/score-protocol), on [midi-protocol](https://github.com/egao1980/midi-protocol). Export writes one track and channel per voice, the tempo map, time and key signatures, lyrics, chord symbols and unfolded repeats, with velocities from dynamics and a per-voice mix for practice files. Import builds the measure map from meta events, quantises onsets to a per-beat grid, spells pitches with [music-theory](https://github.com/egao1980/music-theory), and records every guess in the elements' provenance and confidence.

**Status:** skeleton (0.0.1). The design is in the capability brief [cl-stack/docs/capabilities/score.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/score.md) (slice SC4). The API and tests land through contract branches and team-solve.

```sh
cl-repo test --system score-backend-midi
```

## License

MIT, see [LICENSE](LICENSE).
