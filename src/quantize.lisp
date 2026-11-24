;;;; SC4 quantisation: a grid per beat, chosen through sat-protocol.
;;;;
;;;; (QUANTIZE-ONSETS onsets beats &key (subdivisions +subdivisions+) exact backend)
;;;;   -> (values CHOICES POSITIONS CONFIDENCES)
;;;;
;;;; Arguments (else TYPE-ERROR):
;;;;   ONSETS        a list of rationals (whole notes).
;;;;   BEATS         a non-empty list of beats, each a list (START END UNIT) of
;;;;                 rationals with 0 < END - START <= UNIT, contiguous (each
;;;;                 START is the END before it). Every onset o lies in one beat:
;;;;                 START <= o < END, or o = END of the last beat.
;;;;   SUBDIVISIONS  a non-empty list of distinct members of +SUBDIVISIONS+.
;;;;   EXACT         a generalized boolean (below).
;;;;   BACKEND       a SAT-BACKEND or NIL (SAT-PROTOCOL:*SAT-BACKEND*).
;;;; Results, fresh lists:
;;;;   CHOICES       one subdivision count s per beat, in beat order (with
;;;;                 EXACT, NIL for a beat that no allowed grid fits).
;;;;   POSITIONS     one per onset, in ONSETS order: the onset snapped to the
;;;;                 grid its beat chose (with EXACT, the onset itself).
;;;;   CONFIDENCES   one rational 0..1 per onset, in ONSETS order.
;;;;
;;;; Grid. A beat (START END UNIT) divided by s has the step h = UNIT / s and
;;;; the points START + k * h, k = 0, 1, ..., that are below END, plus END. A
;;;; full beat (END = START + UNIT) has s + 1 points; a beat cut short by a
;;;; barline keeps its step. Snapping a position x in the beat to s gives the
;;;; point nearest to x, the later of two equally near; its deviation is
;;;; |x - point|. The import snaps note ends the same way (import.lisp).
;;;;
;;;; Kinds. A beat is :DOTTED when the numerator of UNIT in lowest terms is 3
;;;; (3/8, 3/4, 3/16), else :SIMPLE. s is a tuplet subdivision of the beat when
;;;; +TUPLET-RATIOS+ lists it under the beat's kind (simple: 3 and 6, ratio 3/2;
;;;; dotted: 2, 4 and 8, ratio 2/3), else natural.
;;;;
;;;; Cost. With D, L and T the :DEVIATION, :LEVEL and :TUPLET of +GRID-WEIGHTS+:
;;;;   cost(b, s) = sum over the onsets o of beat b of floor(D * dev(o, s) / UNIT + 1/2)
;;;;                + L * omega(s) + T * (1 if s is a tuplet of b, else 0)
;;;; where omega(s) counts the prime factors of s with multiplicity (1: 0, 2: 1,
;;;; 3: 1, 4: 2, 6: 2, 8: 3). The first term is onset deviation in thousandths
;;;; of a beat, the rest notation complexity (brief: "cost = onset deviation +
;;;; notation complexity"). The weights were set on humanised renderings
;;;; (tests/fixtures/PROVENANCE.md): coarse natural grids first, a triplet
;;;; before a grid two levels finer.
;;;;
;;;; Choice. A beat may choose every s of SUBDIVISIONS; with EXACT, only the s
;;;; whose grid holds every onset of the beat (deviation 0), and when none does
;;;; the beat's choice is NIL. Each beat takes the allowed s of least cost, the
;;;; one earliest in SUBDIVISIONS on a tie. Beats are independent, so these
;;;; choices are the unique optimum of
;;;;   variables  g(b, s) for every beat b and allowed s;
;;;;   hard       exactly one g(b, s) per beat with an allowed s;
;;;;   objective  (:lex O1 O2), O1 = sum cost(b, s) g(b, s),
;;;;              O2 = sum rank(s) g(b, s), rank(s) = s's 0-based index in
;;;;              SUBDIVISIONS,
;;;; and QUANTIZE-ONSETS finds it with SAT-PROTOCOL:MINIMIZE, passing BACKEND:
;;;; the grid choice is a selection problem, so it goes through the logic family
;;;; (rules-and-logic). How the problem is cut into MINIMIZE calls (one, or one
;;;; per beat) is free, and a beat without onsets may be settled without one
;;;; (its cost is the complexity alone); but at least one MINIMIZE call is made
;;;; whenever some beat holds an onset, and SAT-PROTOCOL:SAT-NO-BACKEND then
;;;; reaches the caller when neither BACKEND nor *SAT-BACKEND* is set.
;;;;
;;;; Confidence. For a beat b, its margin is m(b) = min(1, (c2 - c1) / L): c1
;;;; the least cost of b, c2 the least cost of the other subdivisions b may
;;;; choose, L the :LEVEL weight; m(b) = 1 when b may choose only one. An
;;;; onset o of b snapped with step h to the point p has the confidence
;;;;   min(1 - (2 |o - p| / h)^2, m(b))
;;;; exactly: 1 on the grid of a clear choice, 0 midway between two points or
;;;; when two subdivisions cost the same. So an onset is uncertain when it sits
;;;; far from its point, or when another grid read the beat nearly as well (a
;;;; late note that a finer grid catches). With EXACT every confidence is 1.

(in-package #:score-backend-midi)

;;; Argument types ----------------------------------------------------------------

(defun %rational-list-p (object)
  (%proper-list-of-p object #'rationalp))

(defun %beat-p (object)
  "A beat (START END UNIT) of rationals with 0 < END - START <= UNIT."
  (and (%proper-list-of-p object #'rationalp)
       (= 3 (length object))
       (destructuring-bind (start end unit) object
         (and (plusp (- end start)) (<= (- end start) unit)))))

(defun %beats-p (object)
  "A non-empty list of contiguous beats (file header)."
  (and (consp object)
       (%proper-list-of-p object #'%beat-p)
       (loop for (a b) on object
             while b
             always (= (second a) (first b)))))

(defun %subdivisions-p (object)
  "A non-empty list of distinct members of +SUBDIVISIONS+."
  (and (consp object)
       (%proper-list-of-p object (lambda (s) (member s +subdivisions+)))
       (= (length object) (length (remove-duplicates object)))))

(defun %check-onset (onset low high)
  "ONSET, once it lies in LOW..HIGH (the beats): else TYPE-ERROR inside a
STORE-VALUE restart whose value is checked again."
  (loop until (and (rationalp onset) (<= low onset high))
        do (restart-case (error 'type-error :datum onset
                                            :expected-type `(rational ,low ,high))
             (store-value (value)
               :report "Use another onset (checked again)."
               :interactive (lambda ()
                              (format *query-io* "~&Onset: ")
                              (finish-output *query-io*)
                              (list (read *query-io*)))
               (setf onset value))))
  onset)

;;; Grid, kinds, cost ----------------------------------------------------------------

(defun %beat-start (beat) (first beat))
(defun %beat-end (beat) (second beat))
(defun %beat-unit (beat) (third beat))

(defun %grid-step (beat s)
  (/ (%beat-unit beat) s))

(defun %grid-points (beat s)
  "START + k * h below END, then END (Grid)."
  (let ((h (%grid-step beat s)) (end (%beat-end beat)))
    (append (loop for p = (%beat-start beat) then (+ p h)
                  while (< p end)
                  collect p)
            (list end))))

(defun %snap (x beat s)
  "The point of BEAT's grid for S nearest to X, the later of two equally near."
  (let ((best nil))
    (dolist (p (%grid-points beat s) best)
      (when (or (null best) (<= (abs (- x p)) (abs (- x best))))
        (setf best p)))))

(defun %beat-index (x beats)
  "The index of the beat that holds X: START <= X < END, or the last beat when
X is its END."
  (or (position-if (lambda (beat) (and (<= (%beat-start beat) x) (< x (%beat-end beat)))) beats)
      (and (= x (%beat-end (car (last beats)))) (1- (length beats)))))

(defun %beat-kind (beat)
  (if (= 3 (numerator (%beat-unit beat))) :dotted :simple))

(defun %beat-tuplet (beat s)
  "The tuplet ratio of S in BEAT, or NIL when S is natural there (Kinds)."
  (cdr (assoc s (cdr (assoc (%beat-kind beat) +tuplet-ratios+)))))

(defun %omega (s)
  "The number of prime factors of S, with multiplicity."
  (loop with n = s and count = 0
        for p from 2
        while (> n 1)
        do (loop while (zerop (mod n p))
                 do (setf n (/ n p)) (incf count))
        finally (return count)))

(defun %grid-cost (beat s onsets)
  "cost(b, s) for the ONSETS of BEAT (Cost)."
  (let ((unit (%beat-unit beat)))
    (+ (loop for o in onsets
             sum (floor (+ (/ (* (getf +grid-weights+ :deviation) (abs (- o (%snap o beat s))))
                              unit)
                           1/2)))
       (* (getf +grid-weights+ :level) (%omega s))
       (if (%beat-tuplet beat s) (getf +grid-weights+ :tuplet) 0))))

;;; The choice, through sat-protocol ------------------------------------------------

(defun %grid-choice (costs subdivisions backend memo)
  "The s that SAT-PROTOCOL:MINIMIZE picks for a beat whose allowed subdivisions
cost COSTS, ((s . cost) ...) in SUBDIVISIONS order: variables g(s), exactly
one true, objective (:lex O1 O2), O1 the costs, O2 rank(s). MEMO (EQUAL) holds
the answers of the problems already solved in this call."
  (multiple-value-bind (choice found) (gethash costs memo)
    (if found
        choice
        (let* ((names (mapcar (lambda (cell) (list :grid (car cell))) costs))
               (vars (mapcar #'sat-protocol:sat-var names))
               (model (sat-protocol:minimize
                       (sat-protocol:sat-exactly-one vars)
                       (list :lex
                             (mapcar (lambda (cell var) (cons (cdr cell) var)) costs vars)
                             (mapcar (lambda (cell var)
                                       (cons (position (car cell) subdivisions) var))
                                     costs vars))
                       :backend backend))
               (choice (loop for cell in costs
                             for name in names
                             when (sat-protocol:model-value model name)
                               return (car cell))))
          (when choice
            (setf (gethash costs memo) choice))
          choice))))

(defun %beat-margin (costs choice)
  "m(b): min(1, (c2 - c1) / L), c1 the cost of CHOICE, c2 the least cost of the
other allowed subdivisions; 1 when there is no other."
  (let ((c1 (cdr (assoc choice costs)))
        (others (loop for (s . cost) in costs unless (eql s choice) collect cost)))
    (if others
        (min 1 (/ (- (reduce #'min others) c1) (getf +grid-weights+ :level)))
        1)))

(defun quantize-onsets (onsets beats &key (subdivisions +subdivisions+) exact backend)
  "Choose a subdivision per beat of BEATS for ONSETS and snap them (file header):
(values choices positions confidences)."
  (check-type onsets (satisfies %rational-list-p) "a list of rationals")
  (check-type beats (satisfies %beats-p)
              "a non-empty list of contiguous beats (start end unit), 0 < end - start <= unit")
  (check-type subdivisions (satisfies %subdivisions-p)
              "a non-empty list of distinct members of +SUBDIVISIONS+")
  (check-type backend (or null sat-protocol:sat-backend))
  (let* ((low (%beat-start (first beats)))
         (high (%beat-end (car (last beats))))
         (onsets (mapcar (lambda (o) (%check-onset o low high)) onsets))
         (indices (mapcar (lambda (o) (%beat-index o beats)) onsets))
         (by-beat (make-array (length beats) :initial-element '()))
         (memo (make-hash-table :test 'equal))
         (choices '())
         (margins '()))
    (loop for o in onsets
          for i in indices
          do (push o (aref by-beat i)))
    (loop for beat in beats
          for i from 0
          for os = (reverse (aref by-beat i))
          for allowed = (if exact
                            (remove-if-not (lambda (s) (every (lambda (o) (= o (%snap o beat s))) os))
                                           subdivisions)
                            subdivisions)
          do (if (null allowed)
                 (progn (push nil choices) (push 1 margins))
                 (let* ((costs (mapcar (lambda (s) (cons s (%grid-cost beat s os))) allowed))
                        (choice (%grid-choice costs subdivisions backend memo)))
                   (push choice choices)
                   (push (%beat-margin costs choice) margins))))
    (setf choices (nreverse choices)
          margins (coerce (nreverse margins) 'simple-vector))
    (if exact
        (values choices
                (copy-list onsets)
                (mapcar (constantly 1) onsets))
        (let ((positions '()) (confidences '()))
          (loop for o in onsets
                for i in indices
                for beat = (nth i beats)
                for s = (nth i choices)
                for p = (%snap o beat s)
                for h = (%grid-step beat s)
                do (push p positions)
                   (push (min (- 1 (expt (/ (* 2 (abs (- o p))) h) 2)) (svref margins i))
                         confidences))
          (values choices (nreverse positions) (nreverse confidences))))))
