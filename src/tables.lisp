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

(defparameter +guess-confidence+ 1/2
  "The confidence of a categorical guess: a default meter, a hint that
disagrees with the file, an unprefixed chord symbol, a lyric off its note, a
melody chosen among several candidates.")

(defparameter +flag-below+ 0.8
  "Imported elements with a confidence below this signal LOW-CONFIDENCE-GUESS:
the default threshold of score-protocol's UNCERTAIN-ELEMENTS, the same float,
so both select the same elements.")
