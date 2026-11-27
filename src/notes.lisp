;;;; SC6: timed note events to a score (0.2.0, score-backend-midi#7).
;;;;
;;;; (NOTES-TO-SCORE events &key key meter tempo pickup (subdivisions +subdivisions+)
;;;;                 (source :transcription) backend)  -> (values SCORE FIT)
;;;;
;;;; Notes that come from no SMF: one melodic line of timed events, onsets and
;;;; offsets in seconds and pitches as MIDI numbers with cents, as a monophonic
;;;; transcriber of a recorded melody gives them. SCORE has one part with one
;;;; voice, quantised and spelled by the rules SMF-TO-SCORE uses (import.lisp,
;;;; shared code), every guess carrying a confidence below 1, so
;;;; score-protocol:uncertain-elements is the uncertainty report. FIT, a
;;;; NOTES-FIT, holds the numbers behind the guesses.
;;;;
;;;; Events. EVENTS is a sequence (a list or a vector) of events. An event is a
;;;; property list (a proper list of even length) with
;;;;   :ONSET :OFFSET  reals, seconds, ONSET < OFFSET; any origin (only
;;;;                   differences count);
;;;;   :PITCH          a real, 0 <= PITCH <= 127: the pitch centre as a MIDI
;;;;                   number with cents in its fraction (61.37 is C#4 and 37
;;;;                   cents);
;;;;   :CONFIDENCE     absent or NIL (1), or a real 0..1: the source's own
;;;;                   confidence in the note.
;;;; Other keys are ignored; of a key given twice the first counts (GETF). The
;;;; numbers are taken as RATIONAL, so everything below is exact but FIT-KEY's
;;;; square roots. The events are sorted by onset, stably (equal onsets keep
;;;; EVENTS order); below, "the events" are the checked events in that order.
;;;;
;;;; Arguments (else TYPE-ERROR, from CHECK-TYPE with its STORE-VALUE): EVENTS
;;;; a sequence; KEY a music-theory KEY or NIL; METER a METER or NIL; TEMPO a
;;;; TEMPO or NIL; PICKUP NIL or a non-negative rational; SUBDIVISIONS as for
;;;; QUANTIZE-ONSETS; SOURCE a keyword; BACKEND a SAT-BACKEND or NIL, passed
;;;; to QUANTIZE-ONSETS. They are checked in that order, then PICKUP against
;;;; the bar (impossible hint), then the elements of EVENTS.
;;;;
;;;; Conditions (score-protocol's types, CLHS 9; this backend defines none):
;;;;   impossible hint  PICKUP not shorter than a bar of the meter (Meter):
;;;;                    TYPE-ERROR (EXPECTED-TYPE (rational 0 (bar))) with ERROR
;;;;                    inside a STORE-VALUE restart whose value is checked again
;;;;                    (as for PICKUP's type).
;;;;   bad event        an element of EVENTS that is not an event as above:
;;;;                    SCORE-FORMAT-ERROR, FORMAT :NOTES, REASON "bad event",
;;;;                    POSITION its 0-based index in EVENTS, with ERROR inside
;;;;                    two restarts: USE-VALUE (an event to take in its place,
;;;;                    checked again) and CONTINUE (drop it). The elements are
;;;;                    checked in EVENTS order, before anything else is done.
;;;;   no events        none left (EVENTS empty, or every one dropped):
;;;;                    SCORE-FORMAT-ERROR, FORMAT :NOTES, REASON "no events",
;;;;                    POSITION NIL, with ERROR inside USE-VALUE, whose value (a
;;;;                    sequence of events) replaces EVENTS and is checked from
;;;;                    the start.
;;;;   lost notes       Monophony below: WARN LOSSY-CONVERSION, FORMAT :NOTES,
;;;;                    DIRECTION :FROM, WHAT "notes" (+NOTES-LOSSES+), at most
;;;;                    once, after the quantisation and before the score is
;;;;                    built; MUFFLE-WARNING as for every warning.
;;;;   guesses          LOW-CONFIDENCE-GUESS as SMF-TO-SCORE signals it
;;;;                    (import.lisp, Losses and guesses), WHATs below.
;;;; NOTES-TO-SCORE answers music-theory's NO-KEY-EVIDENCE itself (Pitch).
;;;; AMBIGUOUS-SPELLING (spelling) and SAT-NO-BACKEND (quantisation) reach the
;;;; caller with their own restarts, as in SMF-TO-SCORE.
;;;;
;;;; Pitch. One call (fit-key ((pitch . weight) ...) :hint KEY), music-theory
;;;; MT5, over the events in order, each weighted by its duration OFFSET -
;;;; ONSET in seconds: the key and one global tuning offset are fitted
;;;; together, so a take sung 23 cents sharp reads in its key, not between two.
;;;; Event i gets the MIDI number m_i = (nth i (key-fit-midis fit)), its pitch
;;;; rounded after the offset is removed, and the deviation dev_i = (nth i
;;;; (key-fit-deviations fit)), in cents, -50 <= dev_i < 50. The offset is
;;;; always the take's own (KEY-FIT-OFFSET), with or without a KEY hint: a hint
;;;; names the key to spell in, it never moves a sung note to another
;;;; semitone. When FIT-KEY signals NO-KEY-EVIDENCE (every fold constant:
;;;; the twelve chromatic notes at equal durations), NOTES-TO-SCORE invokes its
;;;; USE-VALUE with NIL: there is no fit, the offset is 0, m_i = floor(pitch +
;;;; 1/2) and dev_i = 100 (pitch - m_i).
;;;; The pitch confidence is pc_i = 1 - (dev_i / 50)^2: 1 in tune (after the
;;;; offset), 0 half a semitone off, below +FLAG-BELOW+ past 22.36 cents.
;;;;
;;;; Key. With KEY, the score's key is KEY, as given (C# major stays C# major).
;;;; It is a guess, +GUESS-CONFIDENCE+, when the fit's KEY-FIT-HINT-DISTANCE is
;;;; not 0: the take fits a transposition of the hint better (-1: sung a
;;;; semitone below it). With no fit it is no guess. Without KEY, the key is
;;;; KEY-FIT-KEY, a guess with KEY-FIT-CORRELATION clamped to 0..1 as its
;;;; confidence; with no fit, C major with confidence 0. Whether to keep the
;;;; hint or move to the sung key is the caller's question; FIT has the
;;;; numbers (KEY-FIT-HINT-DISTANCE, -OFFSET, -CORRELATION).
;;;;
;;;; Meter. M is METER, else 4/4 (make-meter), a guess (+GUESS-CONFIDENCE+).
;;;; Its beat unit u is (beat-unit M), or 1/4 when that is NIL (2+3/8). The
;;;; bar of M is (meter-measure-duration M). P is PICKUP (0 <= P < bar), or 0
;;;; when PICKUP is NIL, a guess (+GUESS-CONFIDENCE+): the first note is taken
;;;; to fall on a downbeat. There is no meter or downbeat detection.
;;;;
;;;; Time. With an origin tau (seconds) and W seconds per whole note, the
;;;; position of a time t is X(t) = max(0, (t - tau) / W), whole notes; tau
;;;; starts at the earliest onset, so the first note is at (or, after the
;;;; fit, next to) 0, the start of the score. The bars are laid as
;;;; SMF-TO-SCORE lays them (measures.lisp, Bars, Meters and lengths) up to
;;;; C = X(the latest offset), from the points ((0 . M)) when P = 0, or ((0 .
;;;; M) (P . M)): then the first bar, 0 .. P, is a pickup (measure 0) when
;;;; there are two bars or more. E is the end of the last bar. The beats are
;;;; SMF-TO-SCORE's (import.lisp, Beats). Snapping the starts is SMF-TO-SCORE's
;;;; (%SNAP-STARTS): the distinct X(onset)s through QUANTIZE-ONSETS with
;;;; SUBDIVISIONS and BACKEND, late starts moved back from E.
;;;;
;;;; Tempo. With TEMPO (bpm b, beat unit w), W = 60 / (b' * w), b' the
;;;; RATIONALIZE of b, for every round below; the tempo mark is TEMPO itself,
;;;; no guess. Without it, b_1 is the bpm of (estimate-tempo onsets
;;;; :beat-unit u) over the events' onsets (tempo.lisp), W_r = 60 / (b_r * u),
;;;; and the tempo mark (make-tempo :bpm b :beat-unit u), b the last round's,
;;;; is a guess (+GUESS-CONFIDENCE+). Either way it is the first measure's one
;;;; tempo mark, at offset 0. There is no tempo tracking: one tempo holds for
;;;; the take.
;;;;
;;;; Alignment. Round r = 1, 2, ...: lay the bars for tau_r and W_r and snap
;;;; the starts, giving the snapped position g of each of the n distinct
;;;; onsets t; tau_1 is the earliest onset. The rounds stop after round r
;;;; when r = +ALIGNMENT-ROUNDS+ (8), or r >= 2 and every g is what it was in
;;;; round r - 1. Otherwise, with the means gm of the g and tm of the t:
;;;;   without TEMPO, when V = sum (g - gm)^2 is not 0, b_(r+1) =
;;;;   floor(100 * 60 / (S u / V) + 1/2) / 100 with S = sum (g - gm)(t - tm):
;;;;   the least-squares slope S / V seconds per whole note, as a tempo to two
;;;;   decimals; else (with TEMPO, or V = 0) b_(r+1) = b_r;
;;;;   tau_(r+1) = tm - W_(r+1) gm, the least-squares origin for that tempo;
;;;; and the rounds also stop when b_(r+1) = b_r and tau_(r+1) = tau_r. The
;;;; result is the last round's: its tau_r, b_r, W_r, bars, choices and
;;;; snapped starts. So the grid, the origin and the tempo are fitted
;;;; together: anchored at the first onset alone, that onset's own error
;;;; moves every note, and ESTIMATE-TEMPO alone can be half a percent off,
;;;; which over 30 beats moves the last notes by a sixth of a beat.
;;;;
;;;; Monophony. Events whose starts snapped to the same position are one
;;;; place in a single line: of each such group the event with the greatest
;;;; OFFSET - ONSET is kept, the earliest in order on a tie, and the others
;;;; are dropped (lost notes, above). A short glitch next to a held note loses
;;;; to the note. The kept events are the notes.
;;;;
;;;; Ends. A note with snapped start g, n the next greater snapped start of
;;;; the notes (or E): its end is (%snapped-end g X(OFFSET) n t beats choices E)
;;;; (import.lisp, Quantisation: cut at n, snapped to its beat's grid unless
;;;; at E, at least one step of g's grid); then, when n - end <
;;;; +LEGATO-GAP+ (an eighth note), the end is n. So overlapping events are
;;;; cut where the next note starts, and a rest shorter than an eighth
;;;; between two notes, or before E, is absorbed into the note before it
;;;; (legato; sung notes rarely last their value). Absorbing is not a guess.
;;;;
;;;; The voice. One part with one staff and one voice, no names, clef :TREBLE
;;;; when the mean of the notes' m_i is at least 60, else :BASS (tracks.lisp,
;;;; Staves). The notes become events, rests, ties at barlines and tuplets as
;;;; in SMF-TO-SCORE (import.lisp, Events), and are spelled there (Spelling,
;;;; Spelling confidence) from their m_i in the key above (the first
;;;; measure's KEY; later measures have none). The score has no metadata, no
;;;; lyrics and no chord symbols.
;;;;
;;;; Confidence. A note's q is its start's quantisation confidence, sp its
;;;; spelling confidence, pc its pitch confidence, c its event's :CONFIDENCE.
;;;; A note event (each tied piece) has min(q, sp, pc, c), its WHAT the
;;;; +NOTE-GUESSES+ entry of the first that is least: "quantization",
;;;; "spelling", "pitch", "input". The first measure has the least of its
;;;; guesses (meter, key, downbeat), its WHAT "meter", "key" or "downbeat",
;;;; the first in that order on a tie; NIL when it has none. The tempo mark:
;;;; +GUESS-CONFIDENCE+ when estimated, WHAT "tempo", else NIL. Every other
;;;; element: NIL.
;;;;
;;;; Provenance and ids. Every element has the provenance (make-provenance
;;;; :source SOURCE :backend +provenance-backend+); a note event (each tied
;;;; piece) also has :TIME-RANGE (ONSET OFFSET), its event's values as given,
;;;; and a measure (tau + W start, tau + W end), its bar in seconds. Ids are
;;;; minted as SMF-TO-SCORE mints them (import.lisp, %FINISH-SCORE); equal
;;;; input gives SCORE-EQUAL results, whether EVENTS is a list or a vector.
;;;; CHECK-SCORE finds no issue.
;;;;
;;;; FIT. A NOTES-FIT (below): ORIGIN, tau; WHOLE, W; TEMPO, the tempo
;;;; mark's tempo; RANKING, ESTIMATE-TEMPO's ranking (NIL with TEMPO); ROUNDS,
;;;; the number of rounds; KEY-FIT, FIT-KEY's result or NIL; NOTES,
;;;; one entry per element of EVENTS (the sequence finally checked), in its
;;;; order: NIL for an element dropped as a bad event, else (ID MIDI
;;;; DEVIATION), ID the id of the note event of its note's first piece (NIL
;;;; for an event dropped by Monophony), MIDI its m_i and DEVIATION its
;;;; dev_i. The deviations and the hint distance are here, not in the
;;;; elements: score-protocol's provenance has a TIME-RANGE but no slot for
;;;; them.
;;;;
;;;; No rule table: the choices above are argmins and argmaxes with total tie
;;;; orders; the grid choice is QUANTIZE-ONSETS's, through sat-protocol
;;;; (rules-and-logic).

(in-package #:score-backend-midi)

(defstruct (notes-fit (:constructor make-notes-fit) (:copier nil))
  "NOTES-TO-SCORE's second value (file header, FIT). Read-only."
  (origin 0 :type rational :read-only t)
  (whole 1 :type rational :read-only t)
  (tempo nil :type (or null music-theory:tempo) :read-only t)
  (ranking '() :type list :read-only t)
  (rounds 1 :type (integer 1) :read-only t)
  (key-fit nil :type (or null music-theory:key-fit) :read-only t)
  (notes '() :type list :read-only t))

(defun notes-to-score (events &key key meter tempo pickup (subdivisions +subdivisions+)
                                   (source :transcription) backend)
  "A score of one voice from the timed note EVENTS (file header), and the
NOTES-FIT behind its guesses: (values score fit)."
  (declare (ignore events key meter tempo pickup subdivisions source backend))
  (%sc6-pending 'notes-to-score))
