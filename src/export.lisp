;;;; SC4 export: a score as a Standard MIDI File of format 1.
;;;;
;;;; (SCORE-TO-SMF score &key (division +default-division+) (layout :voice)
;;;;               (program +default-program+) programs mix (unfold t) (verse 1)
;;;;               (chord-symbols :text) (default-dynamic :mf))  -> an SMF
;;;; (EXPORT-MIDI score destination &rest keys) is
;;;;   (midi-protocol:write-smf (apply #'score-to-smf score keys) destination)
;;;;   with WRITE-SMF's DESTINATION (NIL for a fresh octet vector, a binary
;;;;   stream, a pathname designator) and return value.
;;;;
;;;; Arguments (else TYPE-ERROR, from CHECK-TYPE):
;;;;   DIVISION        ticks per quarter note, an integer 1..32767.
;;;;   LAYOUT          :VOICE (one track per voice) or :PART (one per part).
;;;;   PROGRAM         the program-change byte 0..127 of every voice.
;;;;   PROGRAMS        an alist (id . program): a voice id, or a part id for all
;;;;                   its voices. A voice's own entry wins over its part's.
;;;;   MIX             an alist (id . plist), ids as for PROGRAMS, plist keys
;;;;                   :VELOCITY (an integer -127..127 added to every note-on
;;;;                   velocity, default 0), :VOLUME (CC7 0..127, default
;;;;                   +DEFAULT-VOLUME+) and :PAN (CC10 0..127, default
;;;;                   +DEFAULT-PAN+). A voice uses its own entry, else its
;;;;                   part's, else none; each missing key takes its default.
;;;;   UNFOLD          T (below), NIL, or a list of entries, each a bar number
;;;;                   (pass 1) or a (bar . pass) cons.
;;;;   VERSE           NIL (no lyrics), an integer >= 1, or :PASS.
;;;;   CHORD-SYMBOLS   :TEXT, :MARKER or NIL.
;;;;   DEFAULT-DYNAMIC a dynamic of +DYNAMIC-VELOCITIES+ whose AFTER isn't NIL.
;;;; Keys of PROGRAMS and MIX are looked up with EQUAL. A key that is not the
;;;; id of a part or voice of SCORE signals UNKNOWN-ELEMENT (ID = the key) with
;;;; ERROR inside a CONTINUE restart that ignores the entry. An UNFOLD entry
;;;; whose bar isn't a bar of SCORE (score-first-bar .. score-last-bar) signals
;;;; INVALID-POSITION (POSITION = the entry) inside a CONTINUE restart that drops
;;;; the entry. SCORE is not validated: CHECK-SCORE issues don't stop an export.
;;;; The entries name SCORE's bars (score-first-bar .. score-last-bar).
;;;;
;;;; Playing order. Repeats, endings and jumps are score-protocol's (SC1): with
;;;; UNFOLD T the export plays S = (score-protocol:unfold score), every bar of
;;;; that view once in order, each with the PASS that UNFOLD's third value gives
;;;; its measure. Its SCORE-ERROR (a D.S. with no segno) reaches the caller.
;;;; With UNFOLD NIL, S is SCORE and every bar is played once in written order,
;;;; pass 1; with a list, S is SCORE and its bars are played in the order and
;;;; with the passes the entries give. Below, the rules read S; the parts,
;;;; voices and their ids are the same in SCORE and its view, so PROGRAMS and
;;;; MIX apply to both.
;;;;
;;;; Timeline. The played bars P_0 .. P_n-1 of S are the (BAR . PASS) entries
;;;; above. P_j starts at U_j = the sum of the BAR-LENGTHs of the bars of P_0 ..
;;;; P_j-1, and U = U_n is the end. A position x (whole notes from U_0 = 0) is at
;;;; tick T(x) = floor(4 * DIVISION * x + 1/2). Every position is computed
;;;; exactly and rounded once, never by summing rounded lengths.
;;;;
;;;; Voices and channels. Voices are numbered k = 0, 1, ... in document order
;;;; (parts in order, each part's voices in order). Voice k plays on channel
;;;; (nth (mod k 15) +midi-channels+). Part i (1-based) is labelled by its
;;;; PART-NAME, or "Part i" when it has none. A voice is labelled by its
;;;; VOICE-NAME; else by its part's label when the part has one voice; else by
;;;; "<part label> <j>", j its 1-based place in the part ("Piano 2").
;;;;
;;;; Tracks. (make-smf :format 1 :division DIVISION :tracks ...): track 0 is
;;;; the conductor track; then LAYOUT :VOICE gives track k + 1 to voice k, and
;;;; :PART gives track i to part i (1-based), holding all of its voices. Every
;;;; track is built with MIDI-PROTOCOL:TRACK-FROM-ABSOLUTE from timed events in
;;;; the order stated below, so events at one tick keep that order, and ends
;;;; with one END-OF-TRACK-EVENT at T(U).
;;;;
;;;; The conductor track, in this order at any one tick:
;;;;   1. At tick 0: a TRACK-NAME-EVENT with the metadata :TITLE, then a
;;;;      COPYRIGHT-EVENT with :COPYRIGHT, each when the score has it.
;;;;   2. TIME-SIGNATURE-EVENT at T(U_j) for every played bar j whose signature
;;;;      differs from bar j-1's, and for j = 0. A bar's signature: with M its
;;;;      BAR-TIME and L its BAR-LENGTH, the sum of M's numerators over M's
;;;;      denominator when L is (meter-measure-duration M); otherwise L written
;;;;      over the smallest power of two d >= M's denominator for which L * d is
;;;;      an integer (a 1/4 pickup in 3/4 is 1/4, a final half bar of 3/4 is
;;;;      2/4, a 1/8 pickup in 6/8 is 1/8). CLOCKS-PER-CLICK is
;;;;      max(1, floor(96 * u)), u = (beat-unit (make-meter :numerators (list
;;;;      numerator) :denominator denominator)): 24 in 4/4 and 2/4, 36 in 6/8,
;;;;      12 in 3/8 and 1/8. THIRTY-SECONDS-PER-QUARTER is 8.
;;;;   3. KEY-SIGNATURE-EVENT at T(U_j) for every played bar j whose BAR-KEY
;;;;      isn't EQUALP to bar j-1's, and for j = 0: SHARPS (key-signature key),
;;;;      MINOR-P true for a :MINOR key.
;;;;   4. TEMPO-EVENT. First, at tick 0, +DEFAULT-TEMPO+ (500000) when the
;;;;      first played bar has no tempo mark with a TEMPO at offset 0. Then, for
;;;;      every played bar j and each of its tempo marks with a TEMPO (BPM b of
;;;;      BEAT-UNIT u), in TEMPO order: at T(U_j + OFFSET), the microseconds per
;;;;      quarter note floor(15000000 / (b * u) + 1/2) (a float b through
;;;;      RATIONALIZE), clamped to 1..16777215. Text-only marks give nothing.
;;;;   5. MARKER-EVENT at T(U_j) with the TEXT of the REHEARSAL mark of every
;;;;      played bar j that has one.
;;;;   6. CHORD-SYMBOLS :TEXT or :MARKER: for every played bar j, each anchor of
;;;;      that bar in track order, at T(U_j + offset), a TEXT-EVENT or a
;;;;      MARKER-EVENT whose text is +CHORD-TEXT-PREFIX+ followed by
;;;;      (print-chord-symbol symbol :dialect :pop).
;;;; Events of one kind at one tick come in played-bar order, then mark order.
;;;;
;;;; A voice's track (LAYOUT :VOICE), in this order at any one tick:
;;;;   1. At tick 0: TRACK-NAME-EVENT (the voice's label), INSTRUMENT-NAME-EVENT
;;;;      (its part's label), then on its channel PROGRAM-CHANGE-EVENT, and
;;;;      CONTROL-CHANGE-EVENTs for controller 7 (volume) and 10 (pan), MIX
;;;;      values.
;;;;   2. NOTE-OFF-EVENTs (velocity 0), ascending by key.
;;;;   3. LYRIC-EVENTs.
;;;;   4. NOTE-ON-EVENTs, ascending by key.
;;;; A part's track (LAYOUT :PART): at tick 0 TRACK-NAME-EVENT and
;;;; INSTRUMENT-NAME-EVENT both with the part's label, then for each of its
;;;; voices in order its program change, CC7 and CC10; at every tick the
;;;; note-offs of all its voices (ascending by channel, then key), their lyrics
;;;; (in voice order), and their note-ons (ascending by channel, then key).
;;;;
;;;; Notes. A voice's playback sequence is, for every played bar j in order,
;;;; the events of its voice measure for that bar (index bar - first bar; a
;;;; missing voice measure is silent, one past the measure map is never
;;;; played) that are not grace events, each at onset U_j + its offset (the
;;;; durations of the non-grace events before it in the voice measure). Rests
;;;; sound nothing. A note event sounds its pitch, a chord event each of its
;;;; chord notes (two chord notes with one MIDI key sound once, the first). A
;;;; note's key is (pitch-midi (note-pitch n)); one outside 0..127 isn't written.
;;;; Ties: a note n (a note event or a chord note) continues into the next
;;;; event of the playback sequence when that event starts at n's end (onset +
;;;; duration) and is, or holds, the note whose id is (tie-end (note-tie n)),
;;;; with n's key. A chain of continuations sounds once, from its first note's
;;;; onset to its last note's end, with its first note's velocity. Each sounding
;;;; note gives a NOTE-ON-EVENT at T(onset) and a NOTE-OFF-EVENT, velocity 0, at
;;;; T(end), or at T(onset) + 1 when rounding made T(end) <= T(onset).
;;;;
;;;; Velocity. Per voice a dynamic in force runs along the playback sequence
;;;; (rests included), starting at DEFAULT-DYNAMIC. An event with a DYNAMIC d
;;;; gives its notes d's VELOCITY (+DYNAMIC-VELOCITIES+); after it, d's AFTER is
;;;; in force unless AFTER is NIL (an accent: sf, sfz, fz, rf, rfz). Other events
;;;; give the VELOCITY of the dynamic in force. Then the mix :VELOCITY is added
;;;; and the result clamped to 1..127. Hairpins, articulations and fermatas
;;;; change neither velocity nor timing.
;;;;
;;;; Lyrics. VERSE v (an integer): every sounding event (a note or chord event)
;;;; of the playback sequence with a lyric of verse v gives a LYRIC-EVENT at
;;;; T(onset), continued notes included. VERSE :PASS: v is the PASS of the
;;;; played bar. VERSE NIL: no lyrics. The text is the lyric's TEXT, followed by
;;;; "-" when its SYLLABIC is :BEGIN or :MIDDLE. Extenders are not written.
;;;;
;;;; Losses. After building the SMF and before returning it, SCORE-TO-SMF WARNs
;;;; LOSSY-CONVERSION (FORMAT :MIDI) once per category that applies, in
;;;; +EXPORT-LOSSES+ order, WHAT = its string:
;;;;   "ids"              always: ids, provenance and confidence have no place
;;;;                      in an SMF;
;;;;   "grace notes"      a grace event in a played bar (none is written);
;;;;   "tick rounding"    a position written whose 4 * DIVISION * x is not an
;;;;                      integer (bar starts, note ends, lyrics, tempo, chords);
;;;;   "pitch range"      a sounding note outside MIDI 0..127;
;;;;   "tempo range"      a tempo clamped to 1..16777215;
;;;;   "shared channels"  more than 15 voices.
;;;; The rest of the notation (slurs, hairpins, articulations, fermatas, breath
;;;; marks, extenders, stems, clefs, accidental display, tuplets, measure
;;;; numbers, jumps and endings once unfolded, metadata other than title and
;;;; copyright, text-only tempo marks, the verses not chosen) is dropped without
;;;; a warning.

(in-package #:score-backend-midi)

(defun score-to-smf (score &key (division +default-division+) (layout :voice)
                                (program +default-program+) programs mix (unfold t)
                                (verse 1) (chord-symbols :text) (default-dynamic :mf))
  "SCORE as a midi-protocol SMF of format 1 (file header)."
  (declare (ignorable score division layout program programs mix unfold verse
                      chord-symbols default-dynamic))
  (%sc4-pending 'score-to-smf))

(defun export-midi (score destination &rest keys)
  "Write SCORE-TO-SMF of SCORE and KEYS to DESTINATION with midi-protocol's WRITE-SMF."
  (declare (ignorable score destination keys))
  (%sc4-pending 'export-midi))
