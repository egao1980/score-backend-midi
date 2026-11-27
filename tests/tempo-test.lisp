;;;; SC6 (0.2.0) ESTIMATE-TEMPO (src/tempo.lisp), and the takes the SC6 tests
;;;; share. A take is a list of timed note events rendered here from the
;;;; notation of sc4-performances.sexp's ten public-domain melodies (their
;;;; TRUTH rows: start, end, pitch name, MIDI number, in whole notes after a
;;;; padding that puts the pickup on its beat). Rendering, all exact:
;;;;   W = 60 / (bpm * u) seconds per whole note, u the beat unit of the
;;;;   melody's meter (3/8 in 6/8: the rows' bpm count dotted quarters);
;;;;   onset = 3/2 s + (start - first start) * W + jitter, offset = onset +
;;;;   (end - start) * W * HOLD (9/10 unless a row says otherwise);
;;;;   pitch = MIDI + semitones + (cents + detune) / 100.
;;;; Jitter (whole milliseconds in -J .. J) and detune (whole cents in -D .. D)
;;;; come from x <- (1103515245 x + 12345) mod 2^31, as sc41-perf-ode.mid's
;;;; (PROVENANCE.md): per note, when enabled, (x >> 8) mod (2J + 1) - J, then
;;;; (x >> 8) mod (2D + 1) - D. Take k of melody i (0-based, file order) is
;;;; seeded with 100 i + k. The expected values come from the notation, from
;;;; hand arithmetic on the file header's formulas, or, for the calibrated
;;;; counts, from a reference implementation of the rules (exact arithmetic,
;;;; so any implementation of the rules gives the same counts); an exact Python
;;;; mirror of the tempo rules agrees with them.

(in-package #:score-backend-midi/tests)

;;; Takes ------------------------------------------------------------------------

(defun melody-row (name)
  (or (find name +performance-rows+ :key #'second :test #'string=)
      (error "no melody ~A" name)))

(defun melody-index (row) (position row +performance-rows+))
(defun melody-meter (row) (mt:parse-meter (fourth row)))
(defun melody-key (row) (mt:parse-key (fifth row)))
(defun melody-bpm (row) (sixth row))
(defun melody-unit (row) (or (mt:beat-unit (melody-meter row)) 1/4))
(defun melody-whole (row) (/ 60 (* (melody-bpm row) (melody-unit row))))

(defun melody-pickup (row)
  "The anacrusis of ROW's melody: a bar less its padding, mod a bar."
  (let ((bar (mt:meter-measure-duration (melody-meter row))))
    (mod (- bar (seventh row)) bar)))

(defun melody-notes (row)
  "((start end midi name) ...) of ROW's notation, whole notes from its first note."
  (let* ((truth (ninth row)) (s0 (first (first truth))))
    (mapcar (lambda (n) (list (- (first n) s0) (- (second n) s0) (fourth n) (third n))) truth)))

(defun lcg (seed)
  "The file header's generator: each call steps x and returns x >> 8."
  (let ((x seed))
    (lambda ()
      (setf x (mod (+ (* 1103515245 x) 12345) (expt 2 31)))
      (ash x -8))))

(defun render (notes whole &key (seed 1) (jitter 0) (detune 0) (cents 0) (semitones 0)
                                (hold 9/10) (start 3/2))
  "Timed events for NOTES ((start end midi ...) in whole notes) at WHOLE seconds
per whole note (file header)."
  (let ((draw (lcg seed)))
    (loop for (s e midi) in notes
          collect (let* ((j (if (plusp jitter) (- (mod (funcall draw) (1+ (* 2 jitter))) jitter) 0))
                         (d (if (plusp detune) (- (mod (funcall draw) (1+ (* 2 detune))) detune) 0))
                         (onset (+ start (* s whole) (/ j 1000))))
                    (list :onset onset :offset (+ onset (* (- e s) whole hold))
                          :pitch (+ midi semitones (/ (+ cents d) 100)))))))

(defun render-row (row &rest keys &key (k 1) (scale 1) &allow-other-keys)
  "Take K of ROW's melody at SCALE times its tempo; other KEYS go to RENDER."
  (let ((keys (loop for (key value) on keys by #'cddr
                    unless (member key '(:k :scale)) append (list key value))))
    (apply #'render (melody-notes row) (/ (melody-whole row) scale)
           :seed (+ (* 100 (melody-index row)) k) keys)))

(defun onsets-of (events) (mapcar (lambda (e) (getf e :onset)) events))

;;; Tables ------------------------------------------------------------------------

(deftest sc6-tables
  (ok (equal '(40 200) +tempo-range+))
  (ok (eql 1/20 +tempo-kernel+))
  (ok (eql 100 +tempo-prior-center+))
  (ok (equal '(1 2 4 8 16) +tempo-scales+))
  (ok (eql 8 +alignment-rounds+))
  (ok (eql 1/8 +legato-gap+))
  (ok (equal '("notes") +notes-losses+))
  (ok (equal '("quantization" "spelling" "pitch" "input") +note-guesses+)))

;;; The estimator ---------------------------------------------------------------------

(defun clicks (n step &optional (from 0))
  (loop for k below n collect (+ from (* k step))))

(defun bpm-of (onsets &rest keys)
  (mt:tempo-bpm (apply #'estimate-tempo onsets keys)))

(deftest-parametrize estimate-tempo-clicks
    ((label onsets beat-unit bpm)
     ("0.6 s apart" (clicks 20 3/5) 1/4 100)
     ("1.2 s apart: the beat, not its half" (clicks 20 6/5) 1/4 50)
     ("0.4 s apart, 24 onsets: half the tempo" (clicks 24 2/5) 1/4 75)
     ("0.4 s apart, 15 onsets" (clicks 15 2/5) 1/4 75)
     ("0.4 s apart, 14 onsets" (clicks 14 2/5) 1/4 150)
     ("0.9 s apart, dotted quarters" (clicks 12 9/10 7) 3/8 6667/100)
     ("0.6 s apart, floats" (clicks 20 0.6d0) 1/4 100)
     ("unsorted, repeated" (append (clicks 10 3/5) (reverse (clicks 10 3/5))) 1/4 100)
     ("one onset: the prior's centre" '(5/2) 1/4 100)
     ("one onset, dotted quarters" '(5/2) 3/8 6667/100)
     ("no onsets" '() 1/4 100))
  (multiple-value-bind (tempo ranking) (estimate-tempo onsets :beat-unit beat-unit)
    (ok (eql bpm (mt:tempo-bpm tempo)) label)
    (ok (eql beat-unit (mt:tempo-beat-unit tempo)))
    (ok (= 161 (length ranking)))
    (ok (equal (loop for bpm from 40 to 200 collect bpm) (sort (mapcar #'car ranking) #'<)))
    (ok (every (lambda (entry) (and (rationalp (cdr entry)) (>= (cdr entry) 0))) ranking))
    (ok (loop for (a b) on ranking
              while b
              always (or (> (cdr a) (cdr b)) (and (= (cdr a) (cdr b)) (< (car a) (car b)))))
        "greatest score first, ties by bpm")))

(deftest estimate-tempo-scores
  ;; Two onsets 0.6 s apart: one pair, lag 3/5. Hand arithmetic on the file
  ;; header: A(100) = 1, prior(100) = 1. At 99, p = 20/33 and A = 1 - (20/33 -
  ;; 3/5) * 20 = 29/33; r = 99/100, x = -199/19800, prior = 392040000/392079601.
  ;; At 120 (p = 1/2) the lag is 1/10 away: 0.
  (let ((ranking (nth-value 1 (estimate-tempo '(0 3/5)))))
    (ok (equal '(100 . 1) (first ranking)))
    (ok (eql (* 29/33 392040000/392079601) (cdr (assoc 99 ranking))))
    (ok (eql 0 (cdr (assoc 120 ranking))))
    (ok (eql 0 (cdr (assoc 92 ranking))) "60/92 is 0.0522 s from 0.6: outside the kernel")
    (ok (plusp (cdr (assoc 93 ranking))))))

(deftest estimate-tempo-prior
  ;; The prior alone decides between candidates with equal salience: onsets
  ;; 0, 0.6 and 1.2 hold one lag of 0.6 per pair twice and one of 1.2, so
  ;; A(100) = 2 and A(50) = 1; prior(50) = 16/25. At BEAT-UNIT 1/2 the same
  ;; onsets are 100 half notes per minute, 200 quarters: prior 16/25 too.
  (let ((ranking (nth-value 1 (estimate-tempo '(0 3/5 6/5)))))
    (ok (eql 2 (cdr (assoc 100 ranking))))
    (ok (eql 16/25 (cdr (assoc 50 ranking)))))
  (let ((ranking (nth-value 1 (estimate-tempo '(0 3/5 6/5) :beat-unit 1/2))))
    (ok (eql 32/25 (cdr (assoc 100 ranking))))
    (ok (eql 1 (cdr (assoc 50 ranking))) "50 half notes = 100 quarters: the centre")))

(defun tempo-error (bpm truth) (abs (/ (- bpm truth) truth)))

(deftest-parametrize estimate-tempo-melodies
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  ;; Each melody at its own tempo, three takes with +-30 ms of jitter: the
  ;; candidate is within 4% (the right octave) and the refined tempo within 1%.
  (declare (ignore file title meter key padding end truth expected wrong flagged unflagged))
  (let ((row (melody-row name)))
    (dolist (k '(1 2 3))
      (multiple-value-bind (tempo ranking)
          (estimate-tempo (onsets-of (render-row row :k k :jitter 30)) :beat-unit (melody-unit row))
        (ok (<= (tempo-error (car (first ranking)) bpm) 1/25) (format nil "~A take ~D" name k))
        (ok (<= (tempo-error (mt:tempo-bpm tempo) bpm) 1/100)
            (format nil "~A take ~D: ~A for ~A" name k (mt:tempo-bpm tempo) bpm))))))

(deftest estimate-tempo-octaves
  ;; 90 takes: the ten melodies at 4/5, 1 and 5/4 of their tempo, three each,
  ;; +-30 ms. The prior reads 84 at the notated octave; the other 6 are the
  ;; slow eighth-note Amazing Grace read twice as fast and the fast Ode to Joy
  ;; and Jingle Bells read at half speed: the half-and-double ambiguity a
  ;; :TEMPO hint settles. Every candidate is within 4% of the tempo or of its
  ;; double or half.
  (let ((right 0) (octave 0) (other 0) (missed '()))
    (dolist (row +performance-rows+)
      (dolist (scale '(4/5 1 5/4))
        (dolist (k '(1 2 3))
          (let* ((truth (* scale (melody-bpm row)))
                 (candidate (car (first (nth-value 1 (estimate-tempo
                                                      (onsets-of (render-row row :k k :scale scale :jitter 30))
                                                      :beat-unit (melody-unit row)))))))
            (cond ((<= (tempo-error candidate truth) 1/25) (incf right))
                  ((or (<= (tempo-error candidate (* 2 truth)) 1/25)
                       (<= (tempo-error candidate (/ truth 2)) 1/25))
                   (incf octave)
                   (push (list (second row) scale) missed))
                  (t (incf other)))))))
    (ok (= 84 right) (format nil "~D at the notated octave, misses ~S" right missed))
    (ok (= 6 octave))
    (ok (zerop other))))

(deftest-parametrize estimate-tempo-arguments
    ((label thunk)
     ("onsets not a list" (lambda () (estimate-tempo 3/5)))
     ("an onset not a real" (lambda () (estimate-tempo '(0 :x))))
     ("a dotted list" (lambda () (estimate-tempo '(0 . 1))))
     ("beat unit 0" (lambda () (estimate-tempo '(0 1) :beat-unit 0)))
     ("negative beat unit" (lambda () (estimate-tempo '(0 1) :beat-unit -1/4)))
     ("float beat unit" (lambda () (estimate-tempo '(0 1) :beat-unit 0.25))))
  (ok (signals-type thunk 'type-error) label))
