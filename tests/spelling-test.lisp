;;;; SC4 spelling on import: the brief's "a key hint improves spelling". The
;;;; melodies are diatonic in C# major and Gb major, so MT4's rule S1 spells
;;;; every note from the key in force. Without a hint the key is detected:
;;;; generate-sc4.py ranks the 24 keys with the Krumhansl-Kessler profiles and
;;;; checked the winner against music21's KrumhanslKessler analysis (Db major
;;;; and F# major, the candidates MT4 spells with fewest accidentals).

(in-package #:score-backend-midi/tests)

(defun pitches-of (score)
  (mapcar #'third (voice-starts score (first (score-voices score)))))

(defun first-measure (score) (fset:first (sp:score-measure-map score)))

(deftest key-hint-improves-spelling
  (destructuring-bind (key detected r notes) (import-facts "sc4-spell-c-sharp.mid")
    (let ((plain (import-quietly (fixture-octets "sc4-spell-c-sharp.mid")))
          (hinted (import-quietly (fixture-octets "sc4-spell-c-sharp.mid") :key (mt:parse-key key)))
          (written (mapcar #'third notes)))
      (ok (equal "Db major" detected))
      (ok (equal "Db major" (mt:key-name (sp:measure-info-key (first-measure plain)))))
      (ok (< (abs (- r (sp:element-confidence (first-measure plain)))) 1d-9)
          "a detected key's confidence is its correlation")
      (ok (equal '("Db4" "F4" "Ab4" "Db5" "C5" "Bb4" "Ab4" "Gb4" "F4" "Eb4" "Db4" "Ab4" "Db4" "F4" "Ab4"
                   "Db4")
                 (pitches-of plain))
          "without the hint: Db major's spellings")
      (ok (equal "C# major" (mt:key-name (sp:measure-info-key (first-measure hinted)))))
      (ok (null (sp:element-confidence (first-measure hinted))) "the hint agrees with the notes")
      (ok (equal written (pitches-of hinted)) "with the hint: as written")
      (ok (> (count t (mapcar #'equal written (pitches-of hinted)))
             (count t (mapcar #'equal written (pitches-of plain))))))))

(deftest key-hint-improves-spelling-flats
  (destructuring-bind (key detected r notes) (import-facts "sc4-spell-g-flat.mid")
    (declare (ignore r))
    (multiple-value-bind (plain guesses)
        (guesses-of (lambda () (import-midi (fixture-octets "sc4-spell-g-flat.mid"))))
      (ok (equal "F# major" detected))
      (ok (equal '("F#4" "A#4" "C#5" "F#5" "E#5" "D#5" "C#5" "B4" "A#4" "G#4" "F#4" "C#5" "F#4" "A#4"
                   "C#5" "F#4")
                 (pitches-of plain)))
      (ok (equal (list (list (sp:element-id (first-measure plain)) "meter" 1/2)) guesses)
          "no time signature: 4/4 assumed, the least confident guess"))
    (let ((hinted (import-quietly (fixture-octets "sc4-spell-g-flat.mid") :key (mt:parse-key key))))
      (ok (equal (mapcar #'third notes) (pitches-of hinted)))
      (ok (equal "Gb major" (mt:key-name (sp:measure-info-key (first-measure hinted))))))))

(deftest key-signature-in-the-file
  (let ((score (import-quietly (fixture-octets "sc4-key-mismatch.mid"))))
    (ok (equal "G major" (mt:key-name (sp:measure-info-key (first-measure score)))))
    (ok (null (sp:element-confidence (first-measure score))))
    (ok (equal (mapcar #'third (first (import-facts "sc4-key-mismatch.mid"))) (pitches-of score)))))

(deftest key-hint-against-the-file
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (import-midi (fixture-octets "sc4-key-mismatch.mid") :key (mt:parse-key "D"))))
    (let ((m0 (first-measure score)))
      (ok (equal "D major" (mt:key-name (sp:measure-info-key m0))) "the hint wins")
      (ok (eql 1/2 (sp:element-confidence m0)) "and the disagreement is recorded")
      (ok (equal (list (sp:element-id m0) "key" 1/2) (first guesses))))))

(deftest ambiguous-spelling-reaches-the-caller
  ;; One G#4 in C major: MT4's rules tie (S7) and signal AMBIGUOUS-SPELLING.
  (let* ((seen '())
         (score (handler-bind ((mt:ambiguous-spelling
                                 (lambda (c)
                                   (push (mt:ambiguous-spelling-midi c) seen)
                                   (use-value (mt:parse-pitch "Ab4") c))))
                  (import-quietly (fixture-octets "sc4-spell-ambiguous.mid")))))
    (ok (equal '(68) seen))
    (ok (equal '("Ab4") (pitches-of score)) "USE-VALUE spells it"))
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (import-midi (fixture-octets "sc4-spell-ambiguous.mid"))))
    (let ((event (fifth (first (voice-starts score (first (score-voices score)))))))
      (ok (equal '("G#4") (pitches-of score)) "unhandled: the sharper spelling")
      (ok (eql 0 (sp:element-confidence event)) "midway between two spellings, outside the key")
      (ok (equal (list (list (sp:element-id event) "spelling" 0)) guesses)))))
