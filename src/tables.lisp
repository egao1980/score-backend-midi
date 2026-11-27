;;;; SC4 data: the numbers and closed sets the rules in the other files name.
;;;; GIVEN (no stubs). Data, not rules: each table is read by one rule, stated
;;;; in the file that uses it.

(in-package #:score-backend-midi)

;;; Export ---------------------------------------------------------------------

(defparameter +default-division+ 480
  "Ticks per quarter note of an exported SMF (SCORE-TO-SMF :DIVISION).")

(defparameter +default-program+ 52
  "Program-change byte (0-based GM program number) of every exported voice
unless :PROGRAMS names another: 52 is Choir Aahs (GM program 53 counted from 1).")

(defparameter +midi-channels+ '(0 1 2 3 4 5 6 7 8 10 11 12 13 14 15)
  "The channels given to voices, in order. Channel 9 is GM percussion and never
used for a voice.")

(defparameter +default-volume+ 100
  "CC7 (channel volume) of a voice whose mix entry has no :VOLUME.")

(defparameter +default-pan+ 64
  "CC10 (pan) of a voice whose mix entry has no :PAN: the centre.")

(defparameter +dynamic-velocities+
  '((:pppp 8 :pppp) (:ppp 20 :ppp) (:pp 33 :pp) (:p 49 :p) (:mp 64 :mp)
    (:mf 80 :mf) (:f 96 :f) (:ff 112 :ff) (:fff 120 :fff) (:ffff 127 :ffff)
    (:fp 96 :p) (:sfp 112 :p)
    (:sf 112 nil) (:sfz 112 nil) (:fz 112 nil) (:rf 104 nil) (:rfz 104 nil))
  "(DYNAMIC VELOCITY AFTER) for every score-protocol dynamic: the note-on
velocity of the notes of an event that carries DYNAMIC, and the dynamic in
force after that event. AFTER NIL: an accent; the dynamic in force before the
event stays in force (export.lisp, Velocity).")

(defparameter +chord-text-prefix+ "chord:"
  "The text that starts an exported chord-symbol text or marker event, before
the symbol printed in the :POP dialect (\"chord:C7\", \"chord:N.C.\"). Import
reads such events as exact chord symbols.")

(defparameter +export-losses+
  '("ids" "grace notes" "tick rounding" "pitch range" "tempo range" "shared channels")
  "LOSSY-CONVERSION WHAT strings of SCORE-TO-SMF, in the order they are
signalled (export.lisp, Losses).")

;;; Import ---------------------------------------------------------------------

(defparameter +subdivisions+ '(1 2 3 4 6 8)
  "QUANTIZE-ONSETS :SUBDIVISIONS default: the counts s a beat may be divided
into, in tie-break order. Any :SUBDIVISIONS list is a non-empty list of
distinct members of this one.")

(defparameter +grid-weights+ '(:deviation 1000 :level 50 :tuplet 30)
  "The integer weights of the grid cost (quantize.lisp, Cost): :DEVIATION per
beat of onset deviation, :LEVEL per prime factor of s, :TUPLET for a tuplet
subdivision. :LEVEL is also the unit of a beat's margin (quantize.lisp,
Confidence).")

(defparameter +tuplet-ratios+
  '((:simple (3 . 3/2) (6 . 3/2))
    (:dotted (2 . 2/3) (4 . 2/3) (8 . 2/3)))
  "Per beat kind, (s . TUPLET) for the subdivisions that are tuplets; every
other subdivision of +SUBDIVISIONS+ is natural for that kind. A beat is
:DOTTED when its duration's numerator in lowest terms is 3 (3/8, 3/4, 3/16),
else :SIMPLE (quantize.lisp, Kinds).")

(defparameter +import-losses+ '("percussion" "lyrics")
  "LOSSY-CONVERSION WHAT strings of SMF-TO-SCORE, in the order they are
signalled (import.lisp, Losses).")

(defparameter +provenance-backend+ "score-backend-midi"
  "PROVENANCE-BACKEND of every imported element (its SOURCE is :MIDI).")

(defparameter +spelling-rule-confidence+
  '((:s0 . :copied) (:s1 . 1) (:s2 . 1) (:s3 . :copied) (:s4 . 1)
    (:s5 . :before) (:s6 . :ambiguity) (:s7 . :ambiguity))
  "Per music-theory spelling rule (the third value of SPELL-SEQUENCE, :S0 ..
:S7), where an imported note's spelling confidence comes from (import.lisp,
Spelling confidence): a number is the confidence; :COPIED the confidence of the
note whose spelling the rule takes; :BEFORE that of the note just before;
:AMBIGUITY 1 minus the note's ambiguity.")

(defparameter +guess-confidence+ 1/2
  "The confidence of a categorical guess: a default meter, a hint that
disagrees with the file, an unprefixed chord symbol, a lyric off its note, a
melody chosen among several candidates; for timed notes (notes.lisp) also an
estimated tempo, an assumed downbeat, a key hint the take doesn't fit.")

(defparameter +note-guesses+ '("quantization" "spelling" "pitch" "input")
  "The WHAT of a note event's confidence, in tie order: the first of its
quantisation q, spelling sp, pitch pc and input c confidences that is least
(import.lisp, Confidence; pc and c are 1 for an SMF note, notes.lisp).")

;;; Timed notes (0.2.0, notes.lisp and tempo.lisp) -------------------------------

(defparameter +tempo-range+ '(40 200)
  "ESTIMATE-TEMPO's candidates: every integer bpm from the first to the second,
in beats of the BEAT-UNIT (tempo.lisp, Candidates).")

(defparameter +tempo-kernel+ 1/20
  "The half-width h, in seconds, of ESTIMATE-TEMPO's triangular kernel: a lag
within h of a beat period counts 1 - |lag - period| / h (tempo.lisp).")

(defparameter +tempo-prior-center+ 100
  "The centre of ESTIMATE-TEMPO's prior, in quarter notes per minute (2.4 s per
whole note): 100 for BEAT-UNIT 1/4, 66.67 for 3/8 (tempo.lisp, Prior).")

(defparameter +tempo-scales+ '(1 2 4 8 16)
  "The largest beat multiple K of each refinement pass of ESTIMATE-TEMPO, in
order (tempo.lisp, Refinement).")

(defparameter +alignment-rounds+ 8
  "The most quantisations NOTES-TO-SCORE makes to fit the origin, and an
estimated tempo, to the grid (notes.lisp, Alignment).")

(defparameter +legato-gap+ 1/8
  "A rest shorter than this (whole notes: an eighth note) between two notes of
NOTES-TO-SCORE is absorbed into the note before it (notes.lisp, Ends).")

(defparameter +notes-losses+ '("notes")
  "LOSSY-CONVERSION WHAT strings of NOTES-TO-SCORE (notes.lisp, Monophony).")

(defparameter +flag-below+ 0.8
  "Imported elements with a confidence below this signal LOW-CONFIDENCE-GUESS:
the default threshold of score-protocol's UNCERTAIN-ELEMENTS, the same float,
so both select the same elements.")
