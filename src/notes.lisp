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

;;; Drafts ---------------------------------------------------------------------------
;;; Each checked event is one %TAKE, so the sorted order (pitch, time, notes) and
;;; the EVENTS order (FIT) hold the same objects. Each alignment round is one
;;; %ROUND value, and the rounds return the last one as it was computed.

(defstruct (%take (:constructor %make-take (index given-onset given-offset onset offset pitch c))
                  (:copier nil) (:predicate nil))
  "A checked event (Events): its INDEX in EVENTS, its :ONSET and :OFFSET as
given (GIVEN-ONSET, GIVEN-OFFSET: provenance), and as rationals ONSET, OFFSET,
PITCH and C, its input confidence; then its MIDI number M, deviation DEV and
pitch confidence PC (Pitch), its snapped start G and quantisation confidence Q
(Time), and LINE, the %LINE of a kept note (Monophony, The voice)."
  index given-onset given-offset onset offset pitch c m dev pc g q (line nil))

(defun %take-length (take)
  "OFFSET - ONSET of TAKE, seconds."
  (- (%take-offset take) (%take-onset take)))

(defstruct (%round (:constructor %make-round (tau whole bpm bars e beats choices gs qs))
                   (:copier nil) (:predicate nil))
  "One round of Alignment: the origin TAU, WHOLE seconds per whole note and the
BPM it came from (NIL with a TEMPO hint); the BARS laid, their end E, the BEATS
and each beat's grid CHOICES; per distinct onset, ascending, its snapped start
in GS and quantisation confidence in QS."
  tau whole bpm bars e beats choices gs qs)

(defun %whole-notes (time tau whole)
  "X(TIME) = max(0, (TIME - TAU) / WHOLE), in whole notes (Time)."
  (max 0 (/ (- time tau) whole)))

;;; Arguments and events ---------------------------------------------------------------

(defun %prompt-value (prompt)
  "A restart's interactive arguments: one form read from *QUERY-IO* after PROMPT."
  (format *query-io* "~&~A: " prompt)
  (finish-output *query-io*)
  (list (read *query-io*)))

(defun %checked-pickup (pickup bar)
  "PICKUP once it is NIL or shorter than BAR: else TYPE-ERROR (EXPECTED-TYPE
(rational 0 (BAR))) inside STORE-VALUE, whose value is checked again, for its
type too (Conditions, impossible hint)."
  (loop
    (check-type pickup (or null (rational 0)))
    (when (or (null pickup) (< pickup bar))
      (return pickup))
    (restart-case (error 'type-error :datum pickup :expected-type `(rational 0 (,bar)))
      (store-value (value)
        :report "Use another pickup (checked again)."
        :interactive (lambda () (%prompt-value "Pickup (whole notes)"))
        (setf pickup value)))))

(defun %event-p (object)
  "True for an event (Events): a proper list of even length whose :ONSET and
:OFFSET are reals with ONSET < OFFSET, whose :PITCH is a real 0..127, and whose
:CONFIDENCE is absent, NIL or a real 0..1."
  (and (%proper-list-of-p object (constantly t))
       (evenp (length object))
       (let ((onset (getf object :onset))
             (offset (getf object :offset))
             (pitch (getf object :pitch))
             (confidence (getf object :confidence)))
         (and (realp onset) (realp offset) (< onset offset)
              (realp pitch) (<= 0 pitch 127)
              (or (null confidence)
                  (and (realp confidence) (<= 0 confidence 1)))))))

(defun %checked-take (event index)
  "The %TAKE of EVENT, the element at INDEX of EVENTS, once it is an event; else
SCORE-FORMAT-ERROR \"bad event\" inside USE-VALUE (another event, checked again)
and CONTINUE (drop it: NIL)."
  (loop
    (when (%event-p event)
      (return (let ((confidence (getf event :confidence)))
                (%make-take index (getf event :onset) (getf event :offset)
                            (rational (getf event :onset)) (rational (getf event :offset))
                            (rational (getf event :pitch))
                            (if confidence (rational confidence) 1)))))
    (restart-case (error 'score-protocol:score-format-error
                         :format :notes :reason "bad event" :position index)
      (use-value (value)
        :report "Use another event in its place (checked again)."
        :interactive (lambda () (%prompt-value "Event"))
        (setf event value))
      (continue ()
        :report "Drop this event."
        (return nil)))))

(defun %checked-takes (events)
  "One %TAKE, or NIL for a bad event dropped, per element of EVENTS, in its order.
When none is left, SCORE-FORMAT-ERROR \"no events\" inside USE-VALUE, whose value
replaces EVENTS and is checked from the start (Conditions)."
  (loop
    (check-type events sequence)
    (let ((takes (loop for event in (coerce events 'list)
                       for index from 0
                       collect (%checked-take event index))))
      (when (some #'identity takes)
        (return takes))
      (restart-case (error 'score-protocol:score-format-error
                           :format :notes :reason "no events" :position nil)
        (use-value (value)
          :report "Use other events (checked from the start)."
          :interactive (lambda () (%prompt-value "Events"))
          (setf events value))))))

;;; Pitch and the first measure's guesses ------------------------------------------------

(defun %fit-pitches (sorted key)
  "FIT-KEY's fit of the SORTED takes, each weighted by its length, with the hint
KEY; NIL when FIT-KEY signals NO-KEY-EVIDENCE, answered here with USE-VALUE NIL.
Sets each take's M, DEV and PC (Pitch)."
  (let ((fit (handler-bind ((music-theory:no-key-evidence
                              (lambda (c) (use-value nil c))))
               (music-theory:fit-key (mapcar (lambda (take)
                                               (cons (%take-pitch take) (%take-length take)))
                                             sorted)
                                     :hint key))))
    (if fit
        (loop for take in sorted
              for m in (music-theory:key-fit-midis fit)
              for dev in (music-theory:key-fit-deviations fit)
              do (setf (%take-m take) m
                       (%take-dev take) dev))
        (dolist (take sorted)
          (let ((m (floor (+ (%take-pitch take) 1/2))))
            (setf (%take-m take) m
                  (%take-dev take) (* 100 (- (%take-pitch take) m))))))
    (dolist (take sorted fit)
      (setf (%take-pc take) (- 1 (expt (/ (%take-dev take) 50) 2))))))

(defun %first-guesses (fit key meter pickup)
  "The first measure's guesses (Key, Meter) as (confidence . what), in the order
meter, key, downbeat, so that %LEAST-GUESS takes the first on a tie."
  (remove nil
          (list (and (null meter) (cons +guess-confidence+ "meter"))
                (cond (key
                       (and fit (/= 0 (music-theory:key-fit-hint-distance fit))
                            (cons +guess-confidence+ "key")))
                      (fit
                       (cons (max 0d0 (min 1d0 (music-theory:key-fit-correlation fit))) "key"))
                      (t (cons 0 "key")))
                (and (null pickup) (cons +guess-confidence+ "downbeat")))))

;;; Alignment ---------------------------------------------------------------------------------

(defun %align-round (tau whole bpm onsets latest meter pickup subdivisions backend)
  "One round of Alignment for the origin TAU and WHOLE seconds per whole note
(BPM is recorded): the bars laid up to X(LATEST) from the points of METER and
PICKUP (Time), their beats, and the distinct ONSETS, ascending, snapped
through %SNAP-STARTS. A %ROUND."
  (let ((bars (%lay-bars (%whole-notes latest tau whole)
                         (if (plusp pickup)
                             (list (cons 0 meter) (cons pickup meter))
                             (list (cons 0 meter))))))
    (%set-meters bars)
    (let ((e (%bar-end (car (last bars))))
          (beats (loop for bar in bars append (%bar-beats bar))))
      (multiple-value-bind (gs qs choices)
          (%snap-starts (mapcar (lambda (onset) (%whole-notes onset tau whole)) onsets)
                        beats e subdivisions backend)
        (%make-round tau whole bpm bars e beats choices gs qs)))))

(defun %align (onsets latest tempo bpm unit meter pickup subdivisions backend)
  "(values ROUND R): the rounds of Alignment over the distinct ONSETS
(ascending), from the earliest onset and the TEMPO hint, or, without one, from
the estimate BPM in beats of UNIT. ROUND is the last round as it was computed,
R its number."
  (let ((whole-of (if tempo
                      (constantly (/ 60 (* (rationalize (music-theory:tempo-bpm tempo))
                                           (music-theory:tempo-beat-unit tempo))))
                      (lambda (b) (/ 60 (* b unit)))))
        (n (length onsets))
        (tm (/ (reduce #'+ onsets) (length onsets)))
        (tau (first onsets))
        (previous nil))
    (loop for r from 1
          for current = (%align-round tau (funcall whole-of bpm) bpm onsets latest meter
                                      pickup subdivisions backend)
          for gs = (%round-gs current)
          do (when (or (= r +alignment-rounds+)
                       (and (>= r 2) (equal gs previous)))
               (return (values current r)))
             ;; g never decreases as t grows and the t are distinct, so S > 0
             ;; whenever V /= 0.
             (let* ((gm (/ (reduce #'+ gs) n))
                    (v (loop for g in gs sum (expt (- g gm) 2)))
                    (s (loop for g in gs
                             for onset in onsets
                             sum (* (- g gm) (- onset tm))))
                    (next-bpm (if (or tempo (zerop v))
                                  bpm
                                  (/ (floor (+ (/ (* 6000 v) (* s unit)) 1/2)) 100)))
                    (next-tau (- tm (* (funcall whole-of next-bpm) gm))))
               (when (and (eql next-bpm bpm) (= next-tau tau))
                 (return (values current r)))
               (setf previous gs
                     bpm next-bpm
                     tau next-tau)))))

;;; Monophony, ends, lines --------------------------------------------------------------------

(defun %notes-of (sorted current onsets)
  "Set each of the SORTED takes' G and Q from the round CURRENT (one entry per
distinct onset of ONSETS), then keep, of the takes snapped to one start, the
longest, the earliest on a tie (Monophony). (values NOTES DROPPED-P), NOTES a
fresh list ascending by G."
  (let ((snapped (make-hash-table)) (best (make-hash-table)))
    (loop for onset in onsets
          for g in (%round-gs current)
          for q in (%round-qs current)
          do (setf (gethash onset snapped) (cons g q)))
    (dolist (take sorted)
      (destructuring-bind (g . q) (gethash (%take-onset take) snapped)
        (setf (%take-g take) g
              (%take-q take) q)
        (let ((held (gethash g best)))
          (when (or (null held) (> (%take-length take) (%take-length held)))
            (setf (gethash g best) take)))))
    (let ((notes (remove-if-not (lambda (take) (eq take (gethash (%take-g take) best))) sorted)))
      (values (stable-sort (copy-list notes) #'< :key #'%take-g)
              (/= (length notes) (length sorted))))))

(defun %note-lines (notes current)
  "The %LINE of each of NOTES (ascending by G) in the round CURRENT, its end by
Ends, its PC, C and TIME-RANGE set; each take's LINE is set to it."
  (let ((e (%round-e current))
        (beats (%round-beats current))
        (choices (%round-choices current)))
    (loop for (take next) on notes
          for g = (%take-g take)
          for n = (if next (%take-g next) e)
          for snapped = (%snapped-end g (%whole-notes (%take-offset take) (%round-tau current)
                                                      (%round-whole current))
                                      n t beats choices e)
          for end = (if (< (- n snapped) +legato-gap+) n snapped)
          collect (let ((line (%make-line (%take-m take) g end (%take-index take) (%take-q take))))
                    (setf (%line-pc line) (%take-pc take)
                          (%line-c line) (%take-c take)
                          (%line-time-range line) (list (%take-given-onset take)
                                                        (%take-given-offset take))
                          (%take-line take) line)
                    line))))

;;; Entry point -------------------------------------------------------------------------------

(defun notes-to-score (events &key key meter tempo pickup (subdivisions +subdivisions+)
                                   (source :transcription) backend)
  "A score of one voice from the timed note EVENTS (file header), and the
NOTES-FIT behind its guesses: (values score fit)."
  (check-type events sequence)
  (check-type key (or null music-theory:key))
  (check-type meter (or null music-theory:meter))
  (check-type tempo (or null music-theory:tempo))
  (check-type pickup (or null (rational 0)))
  (check-type subdivisions (satisfies %subdivisions-p)
              "a non-empty list of distinct members of +SUBDIVISIONS+")
  (check-type source keyword)
  (check-type backend (or null sat-protocol:sat-backend))
  (let* ((m (or meter (music-theory:make-meter)))
         (unit (or (music-theory:beat-unit m) 1/4))
         (pickup (%checked-pickup pickup (music-theory:meter-measure-duration m)))
         (takes (%checked-takes events))
         (sorted (stable-sort (copy-list (remove nil takes)) #'< :key #'%take-onset))
         (onsets (%distinct-ascending (mapcar #'%take-onset sorted)))
         (latest (reduce #'max sorted :key #'%take-offset))
         (fit (%fit-pitches sorted key))
         (guesses (%first-guesses fit key meter pickup)))
    (multiple-value-bind (estimate ranking)
        (if tempo
            (values nil '())
            (estimate-tempo (mapcar #'%take-onset sorted) :beat-unit unit))
      (multiple-value-bind (current rounds)
          (%align onsets latest tempo (and estimate (music-theory:tempo-bpm estimate)) unit m
                  (or pickup 0) subdivisions backend)
        (multiple-value-bind (notes dropped) (%notes-of sorted current onsets)
          (when dropped
            (%warn-losses '("notes") +notes-losses+ :format :notes :direction :from))
          (let* ((tau (%round-tau current))
                 (whole (%round-whole current))
                 (bars (%round-bars current))
                 (b0 (first bars))
                 (lines (%note-lines notes current))
                 (mark (or tempo (music-theory:make-tempo :bpm (%round-bpm current) :beat-unit unit)))
                 (guess (%least-guess guesses)))
            (setf (%bar-key b0) (cond (key)
                                      (fit (music-theory:key-fit-key fit))
                                      (t (music-theory:make-key)))
                  (%bar-tempo b0) (list (%make-mark 0 mark (and (null tempo) +guess-confidence+))))
            (when guess
              (setf (%bar-confidence b0) (car guess)
                    (%bar-what b0) (cdr guess)))
            (dolist (bar bars)
              (setf (%bar-time-range bar) (list (+ tau (* whole (%bar-start bar)))
                                                (+ tau (* whole (%bar-end bar))))))
            (%spell-lines lines bars (%bar-keys bars))
            (let* ((measures (%voice-measures lines bars (%round-beats current)
                                              (%round-choices current)))
                   (clef (if (>= (/ (reduce #'+ notes :key #'%take-m) (length notes)) 60)
                             :treble
                             :bass))
                   (parts (list (cons (%make-part-plan nil (list (%make-voice-plan nil nil clef nil)) nil)
                                      (list (%make-voice-draft nil lines measures)))))
                   (score (%finish-score nil bars parts '() :source source))
                   (ids (%minted-note-ids parts score (make-hash-table :test 'equal))))
              (values score
                      (make-notes-fit
                       :origin tau :whole whole :tempo mark :ranking ranking :rounds rounds
                       :key-fit fit
                       :notes (mapcar (lambda (take)
                                        (and take
                                             (list (and (%take-line take)
                                                        (gethash (first (%line-pieces (%take-line take)))
                                                                 ids))
                                                   (%take-m take)
                                                   (%take-dev take))))
                                      takes))))))))))
