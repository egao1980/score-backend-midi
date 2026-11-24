;;;; SC4 import of performances: the brief's "performances recover the notated
;;;; rhythm within a flagged-uncertainty budget". sc4-perf-*.mid are humanised
;;;; renderings of ten melodies written by generate-sc4.py (seeded timing
;;;; errors, 60-100% note lengths; two of them sloppy). sc4-performances.sexp
;;;; holds the notation (the truth) and the import the rules give, computed by
;;;; the script's own implementation of src/quantize.lisp and src/import.lisp.
;;;; Each file has its key signature, every note in that key, so these tests are
;;;; about rhythm (spelling-test.lisp is about keys).

(in-package #:score-backend-midi/tests)

(defparameter +performance-rows+ (fixture-form "sc4-performances.sexp"))

(defun performance-import (file)
  "(score guesses) of importing FILE: its key signature gives the key."
  (multiple-value-list (guesses-of (lambda () (import-midi (fixture-octets file))))))

(deftest performance-table
  (ok (= 10 (length +performance-rows+)))
  (ok (= 254 (reduce #'+ (mapcar (lambda (row) (length (ninth row))) +performance-rows+)))))

(deftest-parametrize performance-rules
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  (declare (ignore title bpm padding wrong flagged unflagged))
  (destructuring-bind (score guesses) (performance-import file)
    (let* ((voice (first (score-voices score)))
           (starts (voice-starts score voice)))
      (ok (equal (list meter key)
                 (list (mt:meter-string (sp:bar-time score 1)) (mt:key-name (sp:bar-key score 1))))
          name)
      (ok (= end (sp:score-duration score)) "the last bar is whole")
      (ok (equal (mapcar (lambda (r) (subseq r 0 3)) expected) (voice-sounding score voice))
          "starts, ends and keys as the rules give them")
      (ok (equal (mapcar #'fourth expected) (mapcar (lambda (s) (sp:element-confidence (fifth s))) starts))
          "each note's confidence is its start's")
      (ok (equal (mapcar #'third truth) (mapcar #'third starts)) "spelled as written")
      (ok (equal (mapcar #'first guesses)
                 (mapcar #'sp:element-id (sp:uncertain-elements score))))
      (ok (every (lambda (g) (equal "quantization" (second g))) guesses))
      (ok (null (sp:check-score score))))))

(deftest-parametrize performance-budget
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  (declare (ignore title meter key bpm padding end expected wrong flagged unflagged))
  (let* ((score (first (performance-import file)))
         (starts (voice-starts score (first (score-voices score))))
         (uncertain (lambda (s) (< (sp:element-confidence (fifth s)) 0.8)))
         (misplaced (loop for s in starts
                          for (onset) in truth
                          unless (= onset (first s)) collect s)))
    (ok (= (length truth) (length starts)) name)
    (ok (every uncertain misplaced) "every onset off the notation is flagged")
    (ok (<= (count-if uncertain starts) (floor (* 2 (length truth)) 5))
        "at most two fifths flagged, the sloppy renderings included")))

(deftest performance-recovery-overall
  (let ((right 0) (flagged 0) (total 0))
    (dolist (row +performance-rows+)
      (let* ((score (first (performance-import (first row))))
             (starts (voice-starts score (first (score-voices score)))))
        (loop for s in starts
              for (onset) in (ninth row)
              do (incf total)
                 (when (= onset (first s)) (incf right))
                 (when (< (sp:element-confidence (fifth s)) 0.8) (incf flagged)))))
    (ok (= 254 total))
    (ok (>= right (* 95/100 total)) (format nil "~D of ~D onsets as notated" right total))
    (ok (<= flagged (* 15/100 total)) (format nil "~D of ~D onsets flagged" flagged total))))

(deftest performance-quantize-options
  (let* ((row (first +performance-rows+))
         (file (first row)) (key (mt:parse-key (fifth row))))
    (ok (sp:score-equal (import-quietly (fixture-octets file) :key key)
                        (import-quietly (fixture-octets file) :key key :quantize t))
        "a performance is never exact: :AUTO snaps it")
    (let* ((raw (import-quietly (fixture-octets file) :key key :quantize nil))
           (smf (mp:read-smf (fixture-octets file))))
      (ok (equal (mapcar (lambda (n) (ticks->whole (first n) 480)) (track-notes (second (mp:smf-tracks smf))))
                 (mapcar #'first (voice-starts raw (first (score-voices raw)))))
          ":QUANTIZE NIL keeps every tick")
      (ok (every (lambda (i) (eq :unnotatable-duration (sp:score-issue-kind i))) (sp:check-score raw))))))
