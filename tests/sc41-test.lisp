;;;; 0.1.1: spelling confidence from the rule that decided the spelling (issue
;;;; #4, music-theory 0.5.2's third value of SPELL-SEQUENCE) and the late last
;;;; note (issue #3, item 1). The rows below are by hand from the header of
;;;; src/import.lisp (Spelling confidence) and music-theory's spell.lisp: the
;;;; pitch and rule of each note are music-theory's, an ambiguity is d/6 with d
;;;; the distance from the note's center to its nearest spelling (C major alone
;;;; has the center 2, each spelled note joins the mean: 60 then 66 in C major
;;;; has the center 7/4 and F#4 the ambiguity 17/24). The two .mid files are
;;;; generate-sc4.py's, their rows in sc41-facts.sexp (the script's own
;;;; quantisation, late starts included).

(in-package #:score-backend-midi/tests)

(defparameter +sc41-facts+ (fixture-form "sc41-facts.sexp"))

(defun sc41-facts (file key)
  (getf (rest (or (assoc file +sc41-facts+ :test #'string=) (error "no facts for ~A" file))) key))

;;; Spelling confidence --------------------------------------------------------

(defun row-key (name)
  "The key named NAME, \"<tonic> major\" or \"<tonic> minor\", any tonic."
  (let ((space (position #\Space name)))
    (mt:make-key :tonic (mt:parse-pitch-class (subseq name 0 space))
                 :mode (if (string= "minor" (subseq name (1+ space))) :minor :major))))

(defun quarter-notes-smf (key midis)
  "Format 1, 480 ticks per quarter: track 0 holds 4/4 and KEY's signature (when
it has one: A# major, ten sharps, has none), track 1 the MIDIS as quarter notes
from 0."
  (let ((sharps (handler-case (mt:key-signature key) (mt:invalid-key () nil))))
    (mp:make-smf
     :format 1 :division 480
     :tracks (list (mp:track-from-absolute
                    (cons (cons 0 (mp:make-time-signature-event :numerator 4 :denominator 4))
                          (and sharps
                               (list (cons 0 (mp:make-key-signature-event
                                              :sharps sharps :minor-p (eq :minor (mt:key-mode key))))))))
                   (mp:track-from-absolute
                    (loop for midi in midis
                          for tick from 0 by 480
                          collect (cons tick (mp:make-note-on-event :key midi :velocity 80))
                          collect (cons (+ tick 480) (mp:make-note-off-event :key midi))))))))

(defparameter +spelling-confidence-rows+
  '(;; Settled by a rule: not flagged.
    ("resolution up" "D major" (62 66 67 68 69) ("D4" "F#4" "G4" "G#4" "A4") (1 1 1 1 1))
    ("resolution down" "C major" (64 63 62) ("E4" "Eb4" "D4") (1 1 1))
    ("chromatic ascent" "C major" (60 61 62 63 64) ("C4" "C#4" "D4" "D#4" "E4") (1 1 1 1 1))
    ("chromatic descent" "C major" (67 66 65 64) ("G4" "Gb4" "F4" "E4") (1 1 1 1))
    ("repeated note" "C major" (68 68 69) ("G#4" "G#4" "A4") (1 1 1))
    ("consistency" "C major" (68 69 64 68 64) ("G#4" "A4" "E4" "G#4" "E4") (1 1 1 1 1))
    ("interval" "C major" (64 68 71) ("E4" "G#4" "B4") (1 1 1))
    ("melodic minor" "A minor" (64 66 68 69) ("E4" "F#4" "G#4" "A4") (1 1 1 1))
    ("lament bass" "G minor" (55 54 53 52 51 50) ("G3" "F#3" "F3" "E3" "Eb3" "D3") (1 1 1 1 1 1))
    ("one side" "A# major" (68) ("G#4") (1))
    ;; Decided by the center or a tie: flagged with 1 - ambiguity, and the
    ;; notes that lean on them with the same confidence.
    ("center" "C major" (60 66 60) ("C4" "F#4" "C4") (1 7/24 1))
    ("copy of a center" "C major" (60 66 60 66 60) ("C4" "F#4" "C4" "F#4" "C4") (1 7/24 1 7/24 1))
    ("interval from a center" "C major" (60 66 68) ("C4" "F#4" "G#4") (1 7/24 7/24))
    ("tie" "C major" (68) ("G#4") (0)))
  "(label key midis pitches confidences): quarter notes in 4/4 with the key's
signature (A# major has none: the hint alone). Each confidence is the note's
sp (the quantisation is exact). By rule: resolution up G#4 :S4; down Eb4 :S4;
ascent C#4 D#4 :S4; descent Gb4 :S4; repeated G#4 :S4 then :S0; consistency
G#4 :S4, the second :S3; interval G#4 :S5 after E4; melodic minor and lament
bass every note :S1 (music-theory 0.5.1's N); one side G#4 :S2; center F#4 :S6
(17/24); its copy :S3; interval from a center G#4 :S5 after F#4; tie :S7.")

(deftest spelling-rule-confidence-table
  (ok (equal '((:s0 . :copied) (:s1 . 1) (:s2 . 1) (:s3 . :copied) (:s4 . 1)
               (:s5 . :before) (:s6 . :ambiguity) (:s7 . :ambiguity))
             +spelling-rule-confidence+)))

(deftest-parametrize spelling-confidence-rows
    ((label key midis pitches confidences) :rows +spelling-confidence-rows+)
  (let ((key (row-key key)))
    (multiple-value-bind (score guesses)
        (guesses-of (lambda () (smf-to-score (quarter-notes-smf key midis) :key key)))
      (let ((starts (voice-starts score (first (score-voices score)))))
        (ok (equal pitches (mapcar #'third starts)) label)
        (ok (equal confidences (mapcar (lambda (s) (sp:element-confidence (fifth s))) starts))
            "each note's confidence from the rule that decided it")
        (ok (equal (loop for s in starts
                         for c in confidences
                         when (< c +flag-below+)
                           collect (list (sp:element-id (fifth s)) "spelling" c))
                   (remove "spelling" guesses :key #'second :test-not #'equal))
            "exactly the notes no rule settled are flagged, as \"spelling\"")))))

(deftest settled-spellings-are-not-flagged
  ;; Issue #4: G#4 rising to A4 in D major is spelled by :S4, so it is not a
  ;; guess. In 0.1.0 it was 1 - 43/60.
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (smf-to-score (quarter-notes-smf (mt:parse-key "D") '(62 66 67 68 69))
                                           :key (mt:parse-key "D"))))
    (let ((sharp (fifth (find "G#4" (voice-starts score (first (score-voices score)))
                              :key #'third :test #'equal))))
      (ok (eql 1 (sp:element-confidence sharp)))
      (ok (null guesses))
      (ok (null (sp:uncertain-elements score))))))

(deftest chord-notes-take-their-rule
  ;; A chord note's confidence is its note's sp. C4 E4 G#4 sounding together
  ;; in C major: the sequence C4 E4 G#4 gives G#4 by :S5 after E4 (sp 1).
  (let ((smf (mp:make-smf
              :format 1 :division 480
              :tracks (list (mp:track-from-absolute
                             (list (cons 0 (mp:make-time-signature-event :numerator 4 :denominator 4))
                                   (cons 0 (mp:make-key-signature-event :sharps 0))))
                            (mp:track-from-absolute
                             (loop for midi in '(60 64 68)
                                   collect (cons 0 (mp:make-note-on-event :key midi :velocity 80))
                                   collect (cons 1920 (mp:make-note-off-event :key midi))))))))
    (multiple-value-bind (score guesses) (guesses-of (lambda () (smf-to-score smf)))
      (let ((chord (find-if (lambda (e) (typep e 'sp:chord-event))
                            (mapcar #'second (voice-events score (first (score-voices score)))))))
        (ok (equal '("C4" "E4" "G#4") (mapcar (lambda (n) (mt:pitch-name (sp:note-pitch n)))
                                              (sp:chord-event-notes chord))))
        (ok (equal '(1 1 1) (mapcar #'sp:element-confidence (sp:chord-event-notes chord))))
        (ok (null (remove "spelling" guesses :key #'second :test-not #'equal)))))))

(deftest settled-spelling-in-an-ensemble
  ;; sc4-strings.mid has no key signature and detects as F major; Violin I
  ;; plays A4 B4 C5, B4 rising a semitone to C5 (:S4). 0.1.0 flagged it (3/8).
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (import-midi (fixture-octets "sc4-strings.mid"))))
    (ok (equal "F major" (mt:key-name (sp:bar-key score 1))))
    (ok (equal '("A4" "B4" "C5") (mapcar #'third (voice-starts score (first (score-voices score))))))
    (ok (null guesses))))

(deftest performance-report-holds-only-guesses
  ;; Issue #4's performance: no time or key signature, D major detected, the
  ;; triplet F#4 G4 G#4 rising to A4 in bar 7. Every spelling is settled (G#4
  ;; by :S4), so each note's confidence is its start's q, and the uncertainty
  ;; report is the assumed 4/4 alone (0.1.0 also listed G#4 at 14/45).
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (import-midi (fixture-octets "sc41-perf-ode.mid"))))
    (let* ((voice (first (score-voices score)))
           (starts (voice-starts score voice))
           (truth (sc41-facts "sc41-perf-ode.mid" :truth))
           (expected (sc41-facts "sc41-perf-ode.mid" :import))
           (sharp (find 68 starts :key #'second))
           (m1 (first-measure score)))
      (ok (= 33 (length starts)))
      (ok (equal "D major" (mt:key-name (sp:bar-key score 1))))
      (ok (equal (sc41-facts "sc41-perf-ode.mid" :end) (sp:score-duration score)))
      (ok (equal (mapcar (lambda (r) (subseq r 0 3)) expected) (voice-sounding score voice))
          "starts, ends and keys as the rules give them")
      (ok (equal (mapcar #'third truth) (mapcar #'third starts)) "spelled as written")
      (ok (equal "G#4" (third sharp)))
      (ok (eql (fourth (find 68 expected :key #'third)) (sp:element-confidence (fifth sharp)))
          "G#4: its start's confidence, not 1 - its ambiguity")
      (ok (equal (mapcar #'fourth expected) (mapcar (lambda (s) (sp:element-confidence (fifth s))) starts))
          "every note's confidence is its start's")
      (ok (equal (list (list (sp:element-id m1) "meter" 1/2)) guesses) "the report: 4/4 assumed, nothing else")
      (ok (equal (mapcar #'first guesses) (mapcar #'sp:element-id (sp:uncertain-elements score))))
      (ok (null (sp:check-score score))))))

;;; The late last note -------------------------------------------------------------

(deftest late-last-note-stays-in-the-last-bar
  ;; sc41-late-last-note.mid: 4/4, C major, C4 D4 E4 on beats 1-3, and F4,
  ;; written on beat 4, played at tick 1882 and released at 1910, before the
  ;; barline (1920). The file ends at 1910, so there is one bar, E = 1. F4's
  ;; start snaps to 1 (quarter grid, q 14039/14400), which no bar holds: it
  ;; moves back to 3/4, the last point below E, with q 1/2. Its lyric stays on
  ;; it. In 0.1.0 the note had no event and placing its lyric failed.
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (import-midi (fixture-octets "sc41-late-last-note.mid"))))
    (let* ((voice (first (score-voices score)))
           (starts (voice-starts score voice))
           (late (fifth (car (last starts)))))
      (ok (= 1 (fset:size (sp:score-measure-map score))) "no bar is added")
      (ok (equal (sc41-facts "sc41-late-last-note.mid" :end) (sp:score-duration score)))
      (ok (equal '((0 1/4 60) (1/4 1/2 62) (1/2 3/4 64) (3/4 1 65)) (voice-sounding score voice))
          "F4 on beat 4, a quarter to the barline")
      (ok (equal (mapcar (lambda (r) (subseq r 0 3)) (sc41-facts "sc41-late-last-note.mid" :import))
                 (voice-sounding score voice))
          "as the generator's rules give it")
      (ok (equal "F4" (third (car (last starts)))))
      (ok (eql 1/2 (sp:element-confidence late)) "+GUESS-CONFIDENCE+, below its start's q")
      (ok (equal (list (list (sp:element-id late) "quantization" 1/2)) guesses))
      (ok (equal '((0 "one" :single) (1/4 "two" :single) (1/2 "three" :single) (3/4 "four" :single))
                 (voice-lyrics score voice))
          "every lyric on its note")
      (ok (null (sp:check-score score))))))

(deftest late-last-note-without-quantisation
  ;; :QUANTIZE NIL keeps the ticks: F4 starts at 941/960, inside the bar, and
  ;; nothing moves.
  (let* ((score (import-quietly (fixture-octets "sc41-late-last-note.mid") :quantize nil))
         (voice (first (score-voices score))))
    (ok (equal '(0 1/4 1/2 941/960) (mapcar #'first (voice-starts score voice))))
    (ok (= 1 (fset:size (sp:score-measure-map score))))))
