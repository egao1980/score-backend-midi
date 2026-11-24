;;;; SC4 import, part 3: from an SMF to a score.
;;;;
;;;; (SMF-TO-SCORE smf &key (parts :all) melody key meter tempo (quantize :auto)
;;;;               (subdivisions +subdivisions+) (lyrics t) (chord-symbols t)
;;;;               backend)  -> a SCORE
;;;; (IMPORT-MIDI source &rest keys) reads SOURCE (an octet vector, a binary
;;;;   input stream or a pathname designator) with MIDI-PROTOCOL:READ-SMF and
;;;;   returns (apply #'smf-to-score smf keys). A MIDI-PARSE-ERROR is answered,
;;;;   from a HANDLER-BIND around READ-SMF, by signalling SCORE-FORMAT-ERROR with
;;;;   ERROR (FORMAT :MIDI, POSITION the error's byte offset, CAUSE the
;;;;   MIDI-PARSE-ERROR): midi-protocol's restarts are still in place, so a
;;;;   handler of SCORE-FORMAT-ERROR may invoke USE-PARTIAL-SMF (or SKIP-CHUNK,
;;;;   SKIP-EVENT, USE-VALUE) and the import goes on with what READ-SMF returns.
;;;;   MIDI-FORMAT-WARNINGs pass through.
;;;;
;;;; Arguments (else TYPE-ERROR): SMF an SMF; PARTS and MELODY as in
;;;; tracks.lisp; KEY, METER and TEMPO a music-theory KEY, METER and TEMPO or
;;;; NIL (hints, measures.lisp); QUANTIZE :AUTO, T or NIL; SUBDIVISIONS as for
;;;; QUANTIZE-ONSETS; LYRICS a generalized boolean; CHORD-SYMBOLS T, :EXACT or
;;;; NIL; BACKEND a SAT-BACKEND or NIL, passed to QUANTIZE-ONSETS.
;;;;
;;;; Steps. Notes, source voices and parts: tracks.lisp. The measure map and
;;;; the end E: measures.lisp. Positions are whole notes, tick / (4 * DIVISION).
;;;;
;;;; Beats. Each bar is divided into the beats of its meter (METER-BEATS) laid
;;;; from the bar's start, the last cut at the bar's end; beat k is (START END
;;;; UNIT) as in quantize.lisp, UNIT the beat's full duration. In bar order the
;;;; beats cover 0 .. E.
;;;;
;;;; Quantisation, per voice, of its notes' starts and ends:
;;;;   QUANTIZE :AUTO  the voice is exact when the position x of every start and
;;;;                   end lies on the grid of lcm(SUBDIVISIONS) of its beat
;;;;                   ((x - START) * lcm / UNIT is an integer; x = E counts).
;;;;                   Exact voices are kept, the others snapped.
;;;;   QUANTIZE T      every voice is snapped.
;;;;   QUANTIZE NIL    every voice keeps its positions; no tuplets; no
;;;;                   QUANTIZE-ONSETS call.
;;;; Kept: the CHOICES of (quantize-onsets X beats :exact t :subdivisions
;;;; SUBDIVISIONS :backend BACKEND), X the voice's distinct starts and ends,
;;;; give the tuplets below; positions don't move and q (the quantisation
;;;; confidence) is 1.
;;;; Snapped: (quantize-onsets S beats ...), S the voice's distinct starts in
;;;; ascending order: POSITIONS are the new starts and CONFIDENCES each start's
;;;; q. The voice is single-line when no two of its notes then share a start.
;;;; A note's end: in a single-line voice first cut to the note's next start
;;;; (the next greater snapped start of the voice, or E); then snapped to the
;;;; grid its beat chose (quantize.lisp, Grid; an end at E stays E); when that
;;;; is at or before the snapped start, it becomes the start plus the step of
;;;; the start's beat grid, cut, in a single-line voice, at the next start.
;;;; Then two notes of one key whose spans overlap (one starts before the other
;;;; ends) are one note, from the earlier start to the later end, with the
;;;; earlier note's q; notes that only touch stay apart.
;;;;
;;;; Events. A voice's boundaries are 0, E, and its notes' starts and ends.
;;;; Between two consecutive boundaries a < b, the notes with start <= a and
;;;; end >= b sound: none gives a rest, one a note event, several a chord event
;;;; (chord notes ascending by key). A note sounding in several spans is cut
;;;; into tied pieces. Each span is then cut, in turn:
;;;;   1. at every barline;
;;;;   2. at the start and end of every beat whose choice is a tuplet s
;;;;      (+TUPLET-RATIOS+, ratio r);
;;;;   3. a piece inside such a beat (step h = UNIT / s): one event with TUPLET
;;;;      r when (duration-dots length :tuplet r) is non-NIL, else the longest
;;;;      notatable prefix of whole steps and then the rest, the same way;
;;;;   4. any other piece: one event when (duration-dots length) is non-NIL;
;;;;      else, when its length and its offset in the bar are multiples of
;;;;      1/128, the pieces of (split-duration length :meter M :offset offset
;;;;      :max-dots 1), M the bar's meter; else one event (CHECK-SCORE reports
;;;;      :UNNOTATABLE-DURATION; only QUANTIZE NIL or grids outside
;;;;      SUBDIVISIONS give such lengths).
;;;; A rest that fills its bar is one rest with MEASURE-REST-P T and DURATION
;;;; the bar's length. Each piece of a note but the last holds a TIE whose END
;;;; is the id of the note of the next piece (a note event, or a chord note of
;;;; that key). Every voice has one voice measure per measure.
;;;;
;;;; Spelling (music-theory MT4). A voice's notes, ordered by start and then
;;;; key, are split into runs of consecutive notes whose starts lie in bars of
;;;; one key (BAR-KEY); each run is spelled by (spell-sequence keys :key that
;;;; key), and all pieces of a note carry its pitch (ACCIDENTAL :AUTO).
;;;; AMBIGUOUS-SPELLING reaches the caller with music-theory's restarts. A
;;;; note's spelling confidence sp is 1 when its pitch is in the key (DEGREE-OF
;;;; gives alteration 0 for the :NATURAL or the :HARMONIC variant), else
;;;; 1 - its ambiguity.
;;;;
;;;; Confidence. A note event: min(q, sp) of its note. A chord event: the least
;;;; q of the notes that start at its onset, or of all its notes when none
;;;; does. A chord note: its note's sp. Rests: NIL. Lyrics: 1 when the lyric's
;;;; tick is its note's start tick, else +GUESS-CONFIDENCE+. Chord-symbol
;;;; anchors: NIL when prefixed, +GUESS-CONFIDENCE+ when guessed. Measures,
;;;; tempo marks: measures.lisp. Parts: tracks.lisp. Staves, voices, ties and
;;;; rehearsal marks: NIL.
;;;;
;;;; Lyrics (LYRICS true). Lyric events are the LYRIC-EVENTs of every track,
;;;; and, in a karaoke file (one with a TEXT-EVENT whose text starts with "@K"),
;;;; its TEXT-EVENTs whose text doesn't start with "@". A lyric event belongs to
;;;; the source voice of its track when the track has exactly one, else (none,
;;;; or several: format 0) to the melody (SMF-TO-SCORE :MELODY, else
;;;; MELODY-VOICE); it is left out when that voice isn't imported. Text, per
;;;; kind:
;;;;   LYRIC-EVENT  characters below code 32 removed and spaces trimmed; a
;;;;                trailing "-" marks a syllable that continues its word, and
;;;;                is removed.
;;;;   karaoke      a leading "/" or "\" (line and paragraph breaks) removed;
;;;;                the syllable starts a word when it then starts with a space,
;;;;                had a break, follows a syllable that ended with a space, or
;;;;                is the voice's first; spaces trimmed.
;;;; Empty texts are dropped. Per voice, in tick order (file order, track by
;;;; track, at one tick), SYLLABIC follows from who continues whom, dropped
;;;; lyrics included: a syllable that continues into the next and doesn't
;;;; continue the one before is :BEGIN, one that does both :MIDDLE, one that
;;;; only continues the one before :END, otherwise :SINGLE. Every lyric is
;;;; verse 1 with no extender. It goes on the first piece of the voice's note
;;;; whose start tick is nearest its tick (the earlier note on a tie); when that
;;;; event already has a lyric it is dropped (LOSSY-CONVERSION "lyrics").
;;;;
;;;; Chord symbols. A TEXT-EVENT or MARKER-EVENT whose text starts with
;;;; +CHORD-TEXT-PREFIX+ is an exact chord symbol, unless CHORD-SYMBOLS is NIL:
;;;; (parse-chord-symbol rest :dialect :pop) of the text after the prefix, its
;;;; errors and warnings reaching the caller with music-theory's restarts
;;;; (SKIP-CHORD-SYMBOL drops it). With CHORD-SYMBOLS T, a TEXT-EVENT that is
;;;; not a karaoke lyric and doesn't start with "@" is a guess when it parses
;;;; in the :POP dialect with neither a CHORD-SYMBOL-PARSE-ERROR nor an
;;;; UNKNOWN-CHORD-QUALITY (both are caught there: such text is not a chord).
;;;; Each becomes an anchor at the position of its tick (the bar holding it and
;;;; the offset from its start, exact); of several at one position, the first.
;;;;
;;;; Metadata. :TITLE is the first TRACK-NAME-EVENT text of track 0 when track
;;;; 0 has no notes, else the text after "@T" of a karaoke file's first "@T"
;;;; event; :COPYRIGHT the first COPYRIGHT-EVENT text of track 0.
;;;;
;;;; Provenance and ids. Every element has the provenance (make-provenance
;;;; :source :midi :backend +provenance-backend+). Every element's id is the
;;;; one MAKE-SCORE mints for it in an id-less copy of the result: its kind's
;;;; prefix and its 1-based place in document order, in base 36 (score-protocol
;;;; ids.lisp); SCORE-ID-COUNTER is the number of elements. Equal input gives
;;;; SCORE-EQUAL results.
;;;;
;;;; Losses and guesses. SMF-TO-SCORE WARNs LOSSY-CONVERSION (FORMAT :MIDI) at
;;;; most once per category of +IMPORT-LOSSES+, in that order: "percussion"
;;;; when notes on channel 9 were dropped, "lyrics" when a lyric was. Then,
;;;; once the score is built, it SIGNALs LOW-CONFIDENCE-GUESS for every element
;;;; whose confidence is below +FLAG-BELOW+, in document order: ELEMENT-ID its
;;;; id, CONFIDENCE its confidence, WHAT "quantization" or "spelling" for a
;;;; note event (whichever of q and sp is less, "quantization" on a tie),
;;;; "quantization" for a chord event, "spelling" for a chord note, "meter" or
;;;; "key" for the first measure (the guess with the least confidence, "meter"
;;;; on a tie), "tempo", "chord symbol", "lyric" and "melody" for tempo marks,
;;;; anchors, lyrics and parts. score-protocol's UNCERTAIN-ELEMENTS then lists
;;;; exactly these elements.
;;;;
;;;; Validity. CHECK-SCORE finds no issue in an imported score except
;;;; :UNNOTATABLE-DURATION (step 4 above).

(in-package #:score-backend-midi)

(defun smf-to-score (smf &key (parts :all) melody key meter tempo (quantize :auto)
                              (subdivisions +subdivisions+) (lyrics t) (chord-symbols t)
                              backend)
  "A score from the midi-protocol SMF SMF (file header)."
  (declare (ignorable smf parts melody key meter tempo quantize subdivisions lyrics
                      chord-symbols backend))
  (%sc4-pending 'smf-to-score))

(defun import-midi (source &rest keys)
  "Read SOURCE with midi-protocol's READ-SMF, then SMF-TO-SCORE with KEYS."
  (declare (ignorable source keys))
  (%sc4-pending 'import-midi))
