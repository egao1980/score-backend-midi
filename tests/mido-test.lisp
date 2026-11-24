;;;; SC4 against mido 1.3.3, live: mido reads what SCORE-TO-SMF writes for every
;;;; fixture (out of process through uv, skipped when uv is absent), and sees
;;;; the notes, lyrics and tempi of the export facts.

(in-package #:score-backend-midi/tests)

(defun mido-dump (octets)
  "What generate-sc4.py --dump prints for OCTETS (SMFs back to back)."
  (multiple-value-bind (code out err)
      (stack-process:run (list "uv" "run" "--no-project" "--with" "mido==1.3.3" "python" "-I"
                               (namestring (fixture-path "generate-sc4.py")) "--dump")
                         :input octets :output :string :error-output :string :timeout 600
                         :env '(("PYTHONIOENCODING" . "utf-8")))
    (values (and (zerop code)
                 (with-standard-io-syntax
                   (let ((*read-eval* nil) (*package* (find-package '#:score-backend-midi/tests)))
                     (read-from-string out))))
            err)))

(defun dump-notes (events)
  "((on off key velocity) ...) from dumped (tick kind channel key velocity) rows."
  (let ((open (make-hash-table :test 'equal)) (out '()))
    (loop for (tick kind channel key velocity) in events
          do (cond ((and (eq kind :note-on) (plusp velocity))
                    (setf (gethash (cons channel key) open)
                          (append (gethash (cons channel key) open) (list (list tick velocity)))))
                   ((member kind '(:note-on :note-off))
                    (let ((start (pop (gethash (cons channel key) open))))
                      (when start (push (list (first start) tick key (second start)) out))))))
    (sort out (lambda (a b) (or (< (first a) (first b))
                                (and (= (first a) (first b)) (< (third a) (third b))))))))

(deftest mido-reads-what-we-write
  (if (not (uv-available-p))
      (skip "uv not found: the live mido cross-read needs uv on PATH")
      (let* ((smfs (mapcar (lambda (name) (export-quietly (fixture-score name))) +export-fixtures+))
             (octets (apply #'concatenate '(vector (unsigned-byte 8)) (mapcar #'smf-octets smfs))))
        (multiple-value-bind (dump err) (mido-dump (coerce octets '(simple-array (unsigned-byte 8) (*))))
          (ok dump err)
          (ok (= (length +export-fixtures+) (length dump)))
          (let ((bad '()))
            (loop for name in +export-fixtures+
                  for (format division tracks) in dump
                  do (unless (and (= 1 format) (= 480 division)) (push (list name :header) bad))
                     (unless (equal (loop for e in (second (first tracks))
                                          when (eq :tempo (second e))
                                            collect (list (first e) (third e)))
                                    (facts name :tempos))
                       (push (list name :tempo) bad))
                     (loop for row in (facts-voices name)
                           for (track-name events) in (rest tracks)
                           do (unless (equal (second row) track-name) (push (list name :name) bad))
                              (unless (equal (sixth row) (dump-notes events))
                                (push (list name (first row) :notes) bad))
                              (unless (equal (mapcar (lambda (l) (list (first l) (second l))) (seventh row))
                                             (loop for e in events
                                                   when (eq :lyric (second e))
                                                     collect (list (first e) (third e))))
                                (push (list name (first row) :lyrics) bad))))
            (ok (null bad) (report bad)))))))
