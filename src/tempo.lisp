;;;; SC6 tempo from onsets in seconds (0.2.0, score-backend-midi#7).
;;;;
;;;; (ESTIMATE-TEMPO onsets &key (beat-unit 1/4))  -> (values TEMPO RANKING)
;;;;
;;;; The beat of a take with no tempo hint: inter-onset intervals weighed
;;;; against every candidate beat period, a prior that prefers moderate tempi,
;;;; then a least-squares refinement over longer and longer lags. NOTES-TO-SCORE
;;;; calls it and then fits the result to the grid (notes.lisp, Alignment).
;;;;
;;;; Arguments (else TYPE-ERROR, from CHECK-TYPE with its STORE-VALUE):
;;;;   ONSETS     a proper list of reals, seconds, in any order, repeats allowed.
;;;;              Each is taken as RATIONAL; below, t1 < t2 < ... < tn are the
;;;;              distinct values. Every quantity below is an exact rational.
;;;;   BEAT-UNIT  a positive rational, the duration a beat counts (1/4 for a
;;;;              quarter, 3/8 for a dotted quarter).
;;;; Results:
;;;;   TEMPO      (make-tempo :bpm b :beat-unit BEAT-UNIT), b from Refinement.
;;;;   RANKING    a fresh list of the candidates as (T . s(T)) conses, s(T) an
;;;;              exact rational, greatest s first, equal scores by T ascending.
;;;;
;;;; Candidates. Every integer T from the first to the second element of
;;;; +TEMPO-RANGE+ (40 .. 200: 161 candidates), in beats of BEAT-UNIT per minute;
;;;; T's beat period is p(T) = 60 / T seconds.
;;;;
;;;; Salience. With h = +TEMPO-KERNEL+ (1/20 s) and the kernel
;;;;   k(d) = max(0, 1 - |d| / h),
;;;; A(T) is the sum of k(tj - ti - p(T)) over all pairs i < j: how often one
;;;; onset follows another one beat later (the onsets' autocorrelation at the
;;;; lag p(T), each lag blurred by h). A take with fewer than two onsets has
;;;; A = 0 everywhere.
;;;;
;;;; Prior. Half and double tempi read the same lags (a pair one beat apart at
;;;; T is two beats apart at T/2), so a prior chooses among them. With T0 =
;;;; +TEMPO-PRIOR-CENTER+ (100) in quarter notes per minute and
;;;;   r = 4 * BEAT-UNIT * T / T0,   x = (r - 1/r) / 2,
;;;;   prior(T) = 1 / (1 + x^2),
;;;; symmetric in log tempo around the centre (r and 1/r give the same x^2;
;;;; x is close to ln r near r = 1) and rational: 1 at 100 quarters per minute,
;;;; 16/25 at 200 and at 50. In whole notes the centre is 2.4 s per whole note
;;;; for every BEAT-UNIT, so a dotted-quarter beat (3/8) is centred at 200/3.
;;;; The score is s(T) = A(T) * prior(T).
;;;;
;;;; Choice. T1 is the first candidate of RANKING when its score is positive.
;;;; When every score is 0 (fewer than two onsets, or no lag within h of any
;;;; candidate period) T1 is the prior's centre, T0 / (4 * BEAT-UNIT).
;;;;
;;;; Refinement. p starts at 60 / T1. For each K of +TEMPO-SCALES+ (1 2 4 8
;;;; 16), in order, one pass over the pairs i < j with lag l = tj - ti: k is
;;;; the nearest integer to l / p, floor(l / p + 1/2); the pair counts when
;;;; 1 <= k <= K and |l - k p| < h, with the weight w = 1 - |l - k p| / h.
;;;; The pass sets p to the weighted least-squares period through the origin,
;;;;   p = (sum of w k l) / (sum of w k^2),
;;;; and leaves p alone when no pair counts. The passes widen the lags they
;;;; trust as p sharpens: a coarse error of a few percent puts multiples of a
;;;; long lag in the wrong place, so they come last.
;;;; Then b = floor(100 * 60 / p + 1/2) / 100: beats per minute to two
;;;; decimals, exact (60 / 0.6 s is 100). It may lie outside +TEMPO-RANGE+.
;;;;
;;;; No rule table: the choice is an argmax with a total tie order, and the
;;;; refinement is arithmetic (rules-and-logic).
;;;;
;;;; Consequences (the tests check them): onsets every 0.6 s give 100 at
;;;; BEAT-UNIT 1/4, and every 1.2 s give 50 (no lag of 0.6 s exists, so only
;;;; the beat or its multiples score, and the prior picks the beat). Fifteen
;;;; or more onsets every 0.4 s give 75, not 150: the take is almost as
;;;; regular at half the tempo, and the prior is nearer the centre there
;;;; (fourteen give 150). A single onset gives 100 (1/4)
;;;; or 66.67 (3/8), the centre, with every score 0.

(in-package #:score-backend-midi)

(defun %real-list-p (object)
  "ESTIMATE-TEMPO's ONSETS: a proper list of reals."
  (%proper-list-of-p object #'realp))

(defun %pair-lags (times)
  "The lags tj - ti of every pair i < j of TIMES (distinct, ascending), as a
sorted simple-vector."
  (sort (coerce (loop for (a . more) on times
                      nconc (mapcar (lambda (b) (- b a)) more))
                'simple-vector)
        #'<))

(defun %first-above (lags x)
  "The index of the first element of LAGS (a sorted simple-vector) greater than
X, or its length."
  (let ((low 0) (high (length lags)))
    (loop while (< low high)
          do (let ((middle (floor (+ low high) 2)))
               (if (> (svref lags middle) x)
                   (setf high middle)
                   (setf low (1+ middle)))))
    low))

(defun %salience (lags period)
  "A(T) for the beat PERIOD (Salience): the kernel sum over LAGS, a sorted
simple-vector. Only the lags strictly within h of PERIOD have a nonzero kernel,
so only they are summed; with none the result is the integer 0."
  (let ((h +tempo-kernel+) (high (+ period +tempo-kernel+)))
    (loop for i from (%first-above lags (- period h)) below (length lags)
          for lag = (svref lags i)
          while (< lag high)
          sum (- 1 (/ (abs (- lag period)) h)))))

(defun %tempo-prior (bpm beat-unit)
  "prior(T) (Prior): 1 / (1 + x^2), x = (r - 1/r) / 2, r = 4 BEAT-UNIT T / T0."
  (let* ((r (/ (* 4 beat-unit bpm) +tempo-prior-center+))
         (x (/ (- r (/ r)) 2)))
    (/ (+ 1 (* x x)))))

(defun %refined-period (lags period)
  "PERIOD after the passes of Refinement over LAGS, one per K of +TEMPO-SCALES+:
each the weighted least-squares period through the origin of the pairs within h
of a multiple k <= K of the period the pass started from."
  (dolist (most +tempo-scales+ period)
    (let ((numerator 0) (denominator 0))
      (loop for lag across lags
            for k = (floor (+ (/ lag period) 1/2))
            for d = (abs (- lag (* k period)))
            when (and (<= 1 k most) (< d +tempo-kernel+))
              do (let ((w (- 1 (/ d +tempo-kernel+))))
                   (incf numerator (* w k lag))
                   (incf denominator (* w k k))))
      (when (plusp denominator)
        (setf period (/ numerator denominator))))))

(defun estimate-tempo (onsets &key (beat-unit 1/4))
  "The tempo of ONSETS (seconds) in beats of BEAT-UNIT, and the ranking of the
candidates (file header): (values tempo ranking)."
  (check-type onsets (satisfies %real-list-p) "a proper list of reals")
  (check-type beat-unit (rational (0)) "a positive rational")
  (let* ((lags (%pair-lags (%distinct-ascending (mapcar #'rational onsets))))
         (ranking (stable-sort
                   (loop for bpm from (first +tempo-range+) to (second +tempo-range+)
                         collect (cons bpm (* (%salience lags (/ 60 bpm))
                                              (%tempo-prior bpm beat-unit))))
                   #'> :key #'cdr))
         (best (first ranking))
         (bpm (if (plusp (cdr best))
                  (car best)
                  (/ +tempo-prior-center+ (* 4 beat-unit))))
         (period (%refined-period lags (/ 60 bpm))))
    (values (music-theory:make-tempo :bpm (/ (floor (+ (/ 6000 period) 1/2)) 100)
                                     :beat-unit beat-unit)
            ranking)))
