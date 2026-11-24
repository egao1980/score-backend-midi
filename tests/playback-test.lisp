;;;; SC4 PLAYBACK-ORDER (src/playback.lisp). Rows: tests/fixtures/sc4-playback.sexp,
;;;; from generate-sc4.py's implementation of the rules, cross-checked with
;;;; music21's expandRepeats (the last column says whether music21 agrees; the
;;;; rows where it doesn't are listed in PROVENANCE.md). Hand rows follow.

(in-package #:score-backend-midi/tests)

(defun case-score (measures)
  "A one-voice 4/4 score with one whole rest per bar and the measures given
as plists (:repeat-start :repeat-end :ending (passes measures) :jump (kinds))."
  (sp:make-score
   :measures (loop for m in measures
                   for first = t then nil
                   collect (sp:make-measure-info
                            :time (and first (mt:parse-meter "4/4"))
                            :key (and first (mt:parse-key "C"))
                            :repeat-start (getf m :repeat-start)
                            :repeat-end (getf m :repeat-end)
                            :ending (let ((e (getf m :ending)))
                                      (and e (sp:make-ending :passes (first e) :measures (second e))))
                            :jump (mapcar (lambda (k) (sp:make-jump-mark :kind k)) (getf m :jump))))
   :parts (list (sp:make-part
                 :staves (list (sp:make-staff))
                 :voices (list (sp:make-voice
                                :measures (loop repeat (length measures)
                                                collect (list (sp:make-rest-event :duration 1)))))))))

(defparameter +playback-rows+ (fixture-form "sc4-playback.sexp"))

(deftest playback-table
  (ok (= 31 (length +playback-rows+)))
  (ok (= 13 (count :fixture +playback-rows+ :key #'second)))
  (ok (= 25 (count t +playback-rows+ :key #'fourth)) "music21 agrees on all but six"))

(deftest-parametrize playback-order-rows
    ((name measures expected agrees) :rows +playback-rows+)
  (declare (ignore agrees))
  (let ((score (if (eq measures :fixture) (fixture-score name) (case-score measures))))
    (ok (equal expected (playback-order score)) name)))

(deftest playback-fresh-and-empty
  (let* ((score (fixture-score "sc0-repeats-voltas"))
         (a (playback-order score)) (b (playback-order score)))
    (ok (equal a b))
    (ok (not (eq a b)) "a fresh list")
    (ok (notany (lambda (x) (member x b :test #'eq)) a) "fresh conses"))
  (ok (null (playback-order (sp:make-score)))))

;;; By hand: the rules, one at a time.
(deftest-parametrize playback-hand-rows
    ((label measures expected)
     ("repeat back to a forward sign" '(() (:repeat-start t) (:repeat-end 2))
      '((1 . 1) (2 . 1) (3 . 1) (2 . 2) (3 . 2)))
     ("a forward sign reopens the section" '((:repeat-start t) (:repeat-start t) (:repeat-end 2))
      '((1 . 1) (2 . 1) (3 . 1) (2 . 2) (3 . 2)))
     ("second section starts after the first's end" '(() (:repeat-end 2) () (:repeat-end 3))
      '((1 . 1) (2 . 1) (1 . 2) (2 . 2) (3 . 1) (4 . 1) (3 . 2) (4 . 2) (3 . 3) (4 . 3)))
     ("first ending of two bars" '((:repeat-start t) (:ending ((1) 2)) (:repeat-end 2) (:ending ((2) 1)))
      '((1 . 1) (2 . 1) (3 . 1) (1 . 2) (4 . 1)))
     ("ending cut at the last bar" '((:repeat-start t) (:repeat-end 2) (:ending ((2) 5)))
      '((1 . 1) (2 . 1) (1 . 2) (2 . 2) (3 . 1)))
     ("ending for passes 1 and 3" '((:repeat-start t) (:repeat-end 3 :ending ((1 3) 1)) (:ending ((2) 1)))
      '((1 . 1) (2 . 1) (1 . 2) (3 . 1)))
     ("dal segno to the latest segno" '((:jump (:segno)) (:jump (:segno)) (:jump (:dal-segno)))
      '((1 . 1) (2 . 1) (3 . 1) (2 . 2) (3 . 2)))
     ("to coda to the first coda after it" '((:jump (:coda)) (:jump (:to-coda)) (:jump (:da-capo-al-coda))
                                             (:jump (:coda)) (:jump (:coda)))
      '((1 . 1) (2 . 1) (3 . 1) (1 . 2) (2 . 2) (4 . 1) (5 . 1)))
     ("al fine after a dal segno" '(() (:jump (:segno :fine)) () (:jump (:dal-segno-al-fine)))
      '((1 . 1) (2 . 1) (3 . 1) (4 . 1) (2 . 2)))
     ("repeats before the jump at one barline" '((:repeat-start t) (:repeat-end 2 :jump (:da-capo-al-fine))
                                                 (:jump (:fine)))
      '((1 . 1) (2 . 1) (1 . 2) (2 . 2) (1 . 3) (2 . 3) (3 . 1)))
     ("a jump is taken once" '(() (:jump (:da-capo)))
      '((1 . 1) (2 . 1) (1 . 2) (2 . 2)))
     ("fine without al fine is played through" '((:jump (:fine)) (:jump (:da-capo)) ())
      '((1 . 1) (2 . 1) (1 . 2) (2 . 2) (3 . 1))))
  (ok (equal expected (playback-order (case-score measures))) label))

(deftest playback-dal-segno-without-segno
  (let* ((score (case-score '(() (:jump (:dal-segno)) (:jump (:segno)))))
         (c (signalled (lambda () (playback-order score)))))
    (ok (typep c 'sp:score-error))
    (ok (equal "no segno" (and c (sp:score-error-reason c))))
    (ok (equal '((1 . 1) (2 . 1) (3 . 1))
               (handler-bind ((sp:score-error #'continue)) (playback-order score)))
        "CONTINUE ignores the jump")))

(deftest playback-pickup-bar-zero
  ;; A pickup is bar 0, and D.C. returns to it.
  (let ((score (sp:make-score
                :measures (list (sp:make-measure-info :time (mt:parse-meter "3/4") :key (mt:parse-key "G")
                                                      :pickup-p t :length 1/4)
                                (sp:make-measure-info)
                                (sp:make-measure-info :jump (list (sp:make-jump-mark :kind :da-capo))))
                :parts (list (sp:make-part :staves (list (sp:make-staff))
                                           :voices (list (sp:make-voice :measures '(() () ()))))))))
    (ok (equal '((0 . 1) (1 . 1) (2 . 1) (0 . 2) (1 . 2) (2 . 2)) (playback-order score)))))
