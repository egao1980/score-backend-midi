;;;; SC4 QUANTIZE-ONSETS (src/quantize.lisp). Rows: tests/fixtures/sc4-quantize.sexp,
;;;; by brute force over every allowed grid in generate-sc4.py (hand cases, then
;;;; seeded random onsets near random grids). The choice must go through
;;;; sat-protocol: a counting backend sees the calls.

(in-package #:score-backend-midi/tests)

(defparameter +quantize-rows+ (fixture-form "sc4-quantize.sexp"))

(defclass counting-backend (sat-backend-cdcl:cdcl-backend)
  ((calls :initform 0 :accessor backend-calls)))

(defmethod sat:backend-solve :before ((backend counting-backend) cnf &key &allow-other-keys)
  (declare (ignore cnf))
  (incf (backend-calls backend)))

(deftest quantize-table
  (ok (= 65 (length +quantize-rows+)))
  (ok (= 17 (count t +quantize-rows+ :key #'fifth)) "exact rows"))

(deftest-parametrize quantize-onsets-rows
    ((label beats onsets subdivisions exact choices positions confidences)
     :rows +quantize-rows+)
  (multiple-value-bind (c p f) (quantize-onsets onsets beats :subdivisions subdivisions :exact exact)
    (ok (equal choices c) label)
    (ok (equal positions p))
    (ok (equal confidences f))))

(deftest quantize-goes-through-sat
  (let ((given (make-instance 'counting-backend))
        (default (make-instance 'counting-backend))
        (beats '((0 1/4 1/4) (1/4 1/2 1/4))))
    (let ((sat:*sat-backend* default))
      (ok (equal '((3 1) (0 1/12 1/6 1/4) (1 1 1 1))
                 (multiple-value-list (quantize-onsets '(0 1/12 1/6 1/4) beats :backend given))))
      (ok (and (plusp (backend-calls given)) (zerop (backend-calls default)))
          "the backend given is used, and the default is not")
      (quantize-onsets '(0 1/8) beats)
      (ok (plusp (backend-calls default)) "*SAT-BACKEND* otherwise"))
    (let ((sat:*sat-backend* nil))
      (ok (signals-type (lambda () (quantize-onsets '(0 1/8) beats)) 'sat:sat-no-backend)
          "no backend: sat-protocol's condition reaches the caller"))))

(deftest quantize-results-are-fresh
  (let ((onsets (list 0 1/8)) (beats (list (list 0 1/4 1/4))))
    (multiple-value-bind (c p f) (quantize-onsets onsets beats)
      (ok (equal '(2) c))
      (ok (not (eq p onsets)))
      (ok (equal '(1 1) f))
      (ok (equal '(0 1/8) onsets) "ONSETS untouched"))))

(deftest-parametrize quantize-argument-errors
    ((label thunk)
     ("onsets not a list" (lambda () (quantize-onsets 0 '((0 1/4 1/4)))))
     ("float onset" (lambda () (quantize-onsets '(0.5) '((0 1 1)))))
     ("no beats" (lambda () (quantize-onsets '() '())))
     ("span over the unit" (lambda () (quantize-onsets '(0) '((0 1/2 1/4)))))
     ("empty beat" (lambda () (quantize-onsets '(0) '((0 0 1/4)))))
     ("gap between beats" (lambda () (quantize-onsets '(0) '((0 1/4 1/4) (1/2 3/4 1/4)))))
     ("onset before the beats" (lambda () (quantize-onsets '(-1/8) '((0 1/4 1/4)))))
     ("onset after the beats" (lambda () (quantize-onsets '(1/2) '((0 1/4 1/4)))))
     ("subdivision 5" (lambda () (quantize-onsets '(0) '((0 1/4 1/4)) :subdivisions '(1 5))))
     ("no subdivisions" (lambda () (quantize-onsets '(0) '((0 1/4 1/4)) :subdivisions '())))
     ("repeated subdivision" (lambda () (quantize-onsets '(0) '((0 1/4 1/4)) :subdivisions '(2 2))))
     ("backend" (lambda () (quantize-onsets '(0) '((0 1/4 1/4)) :backend :cdcl))))
  (ok (signals-type thunk 'type-error) label))

(deftest quantize-end-of-last-beat
  ;; An onset at the END of the last beat belongs to it.
  (ok (equal '((2) (1/4) (1))
             (multiple-value-list (quantize-onsets '(1/4) '((0 1/4 1/4)) :subdivisions '(2))))))

(deftest quantize-exact-without-a-fit
  ;; A quintuplet point fits no grid of (1 2 3 4 6 8): NIL, positions kept.
  (ok (equal '((nil 1) (1/20 1/4) (1 1))
             (multiple-value-list (quantize-onsets '(1/20 1/4) '((0 1/4 1/4) (1/4 1/2 1/4)) :exact t)))))
