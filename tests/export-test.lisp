;;;; SC4 SCORE-TO-SMF and EXPORT-MIDI (src/export.lisp). The golden files
;;;; sc4-export-*.mid and sc4-variant-*.mid were written by mido from the events
;;;; generate-sc4.py derives from the rules, after music21 agreed on every note
;;;; (onset, end, key), the bar order and the tempi (PROVENANCE.md). The facts
;;;; file holds the same events in readable form, so a mismatch says where.

(in-package #:score-backend-midi/tests)

(defun voice-row-notes (row) (sixth row))
(defun voice-row-lyrics (row) (seventh row))

(deftest export-fixture-table
  (ok (= 13 (length +export-fixtures+)))
  (ok (= 13 (length *facts*)))
  (ok (every (lambda (name) (probe-file (fixture-path (export-file name)))) +export-fixtures+)))

(deftest-parametrize export-golden-bytes
    ((name) :rows +export-fixtures+)
  (let ((smf (export-quietly (fixture-score name))))
    (ok (typep smf 'mp:smf))
    (ok (= 1 (mp:smf-format smf)))
    (ok (= 480 (mp:smf-division smf)))
    (ok (= (1+ (length (facts-voices name))) (length (mp:smf-tracks smf))) "conductor + one per voice")
    (ok (equalp (fixture-octets (export-file name)) (smf-octets smf)) "byte for byte")))

(deftest-parametrize export-voice-tracks
    ((name) :rows +export-fixtures+)
  (let* ((smf (export-quietly (fixture-score name)))
         (bad '()))
    (loop for row in (facts-voices name)
          for track in (rest (mp:smf-tracks smf))
          do (destructuring-bind (id label part channel program &rest more) row
               (declare (ignore more))
               (unless (equal (voice-row-notes row) (track-notes track)) (push (list id :notes) bad))
               (unless (equal (mapcar (lambda (l) (subseq l 0 2)) (voice-row-lyrics row))
                              (track-texts track #'mp:lyric-event-p))
                 (push (list id :lyrics) bad))
               (unless (equal label (track-name track)) (push (list id :track-name) bad))
               (unless (equal part (instrument-name track)) (push (list id :instrument) bad))
               (unless (equal (list (list :program channel program) (list 7 channel 100)
                                    (list 10 channel 64))
                              (tick0-channel-events track))
                 (push (list id :channel-setup) bad))
               (unless (every (lambda (n) (= channel (mp:channel-event-channel n)))
                              (mapcar #'cdr (timed-of track (lambda (e) (typep e 'mp:channel-event)))))
                 (push (list id :channel) bad))))
    (ok (null bad) (report bad))))

(deftest-parametrize export-conductor-track
    ((name) :rows +export-fixtures+)
  (let* ((smf (export-quietly (fixture-score name)))
         (conductor (first (mp:smf-tracks smf))))
    (ok (equal (facts name :time-signatures) (time-signatures conductor)))
    (ok (equal (facts name :key-signatures) (key-signatures conductor)))
    (ok (equal (facts name :tempos) (tempos conductor)))
    (ok (equal (facts name :markers) (track-texts conductor #'mp:marker-event-p)))
    (ok (equal (facts name :chords) (track-texts conductor #'mp:text-event-p)))
    (ok (notany (lambda (te) (typep (cdr te) 'mp:channel-event)) (mp:track-to-absolute conductor)))
    (ok (every (lambda (track) (= (facts name :end) (track-end track))) (mp:smf-tracks smf))
        "every track ends at the end of the last played bar")))

(deftest-parametrize export-losses
    ((name) :rows +export-fixtures+)
  (let ((score (fixture-score name)))
    (ok (equal (facts name :losses) (losses-of (lambda () (score-to-smf score)))))
    (ok (every (lambda (f) (eq :midi f)) (lossy-formats (lambda () (score-to-smf score)))))))

(deftest export-titles
  (ok (equal "Amazing Grace"
             (track-name (first (mp:smf-tracks (export-quietly (fixture-score "sc0-pickup")))))))
  (ok (null (track-name (first (mp:smf-tracks
                                 (export-quietly (sp:copy-score (fixture-score "sc0-pickup")
                                                                :metadata '()))))))))

(deftest export-is-deterministic
  (let ((score (fixture-score "sc0-keyboard")))
    (ok (equalp (smf-octets (export-quietly score)) (smf-octets (export-quietly score))))))

;;; Velocity by hand (sc4-dynamics: p, -, mf, sf | -, fp, -, ff | sfz, -, rest
;;; pp, - | mp, sfp, -): an accent returns to the level before it, fp and sfp
;;; leave piano, a rest's dynamic counts.
(deftest export-velocities-by-hand
  (let ((notes (track-notes (second (mp:smf-tracks (export-quietly (fixture-score "sc4-dynamics")))))))
    (ok (equal '(49 49 80 112 80 96 49 112 112 112 33 64 112 49) (mapcar #'fourth notes))))
  (let ((notes (track-notes (second (mp:smf-tracks (export-quietly (fixture-score "sc4-dynamics")
                                                                   :default-dynamic :f))))))
    (ok (equal '(49 49 80 112 80 96 49 112 112 112 33 64 112 49) (mapcar #'fourth notes))
        "the first note sets p: the default never shows")))

(deftest export-default-dynamic
  (let ((notes (track-notes (second (mp:smf-tracks (export-quietly (fixture-score "sc0-pickup")
                                                                   :default-dynamic :pp))))))
    (ok (every (lambda (n) (= 33 (fourth n))) notes))))

;;; Option rows (sc4-variants.sexp).

(defparameter +variant-rows+ (fixture-form "sc4-variants.sexp"))

(deftest-parametrize export-variants
    ((variant fixture options losses) :rows +variant-rows+)
  (multiple-value-bind (smf whats)
      (call-quietly (lambda () (apply #'score-to-smf (fixture-score fixture) options)))
    (ok (equalp (fixture-octets (format nil "sc4-variant-~A.mid" variant)) (smf-octets smf)) variant)
    (ok (equal losses whats))))

(deftest export-part-layout
  (let* ((smf (export-quietly (fixture-score "sc0-satb") :layout :part))
         (track (second (mp:smf-tracks smf))))
    (ok (= 2 (length (mp:smf-tracks smf))))
    (ok (equal "Choir" (track-name track)))
    (ok (equal "Choir" (instrument-name track)))
    (ok (equal '((:program 0 52) (7 0 100) (10 0 64) (:program 1 52) (7 1 100) (10 1 64)
                 (:program 2 52) (7 2 100) (10 2 64) (:program 3 52) (7 3 100) (10 3 64))
               (tick0-channel-events track)))
    (ok (equal (voice-row-notes (third (facts-voices "sc0-satb"))) (track-notes track :channel 2)))))

(deftest export-mix-by-hand
  (let* ((smf (export-quietly (fixture-score "sc0-satb")
                              :mix '(("v-s" :velocity 20 :volume 127 :pan 64)
                                     ("p-5" :volume 70 :pan 20))))
         (tracks (rest (mp:smf-tracks smf))))
    (ok (equal '((:program 1 52) (7 1 127) (10 1 64)) (tick0-channel-events (second tracks))))
    (ok (equal '((:program 0 52) (7 0 70) (10 0 20)) (tick0-channel-events (first tracks))))
    (ok (every (lambda (n) (= 100 (fourth n))) (track-notes (second tracks))) "alto mf + 20")
    (ok (every (lambda (n) (= 80 (fourth n))) (track-notes (third tracks))))))

(deftest export-mix-velocity-clamps
  (let ((loud (export-quietly (fixture-score "sc4-dynamics") :mix '(("v-8" :velocity 100))))
        (soft (export-quietly (fixture-score "sc4-dynamics") :mix '(("p-6" :velocity -127)))))
    (ok (every (lambda (n) (= 127 (fourth n))) (track-notes (second (mp:smf-tracks loud)))))
    (ok (every (lambda (n) (= 1 (fourth n))) (track-notes (second (mp:smf-tracks soft)))))))

(deftest export-unfold-options
  ;; Bars 1-8 hold 4 2 3 2 1 4 2 1 notes; played 1 2 3 4 1 2 5 6 7 6 7 6 8.
  (let ((score (fixture-score "sc0-repeats-voltas")))
    (ok (= 35 (length (track-notes (second (mp:smf-tracks (export-quietly score)))))))
    (ok (= 19 (length (track-notes (second (mp:smf-tracks (export-quietly score :unfold nil)))))))
    (ok (= 6 (length (track-notes (second (mp:smf-tracks (export-quietly score :unfold '(1 (2 . 1)))))))))))

(deftest export-verse-per-pass
  ;; Played (1 . 1) (2 . 1) (3 . 1) (1 . 2) (2 . 2) (4 . 1): verse 1, verse 2,
  ;; then the second ending's first time, which has no verse 1.
  (let ((lyrics (track-texts (second (mp:smf-tracks (export-quietly (fixture-score "sc4-strophic")
                                                                    :verse :pass)))
                             #'mp:lyric-event-p)))
    (ok (equal '("Joy" "to" "the" "world" "the" "Lord" "Let" "ev-" "ery" "heart" "pre-")
               (mapcar #'second lyrics)))))

(deftest export-chord-text
  (let ((conductor (first (mp:smf-tracks (export-quietly (fixture-score "sc0-chords-under-rests"))))))
    (ok (equal '("chord:F" "chord:C7" "chord:Bb" "chord:Gm7" "chord:C7(b9)" "chord:F/A" "chord:F"
                 "chord:N.C.")
               (mapcar #'second (track-texts conductor #'mp:text-event-p))))
    (ok (equal '(0 480 1920 2880 3840 4800 5760 7200)
               (mapcar #'first (track-texts conductor #'mp:text-event-p))))))

(deftest export-actual-length-signatures
  ;; Amazing Grace: a 1/4 pickup and a half-bar final measure in 3/4.
  (ok (equal '((0 1 4 24) (480 3 4 24) (4800 2 4 24))
             (time-signatures (first (mp:smf-tracks (export-quietly (fixture-score "sc0-pickup")))))))
  ;; The carol: a 1/8 pickup and a 5/8 final measure in 6/8.
  (ok (equal '((0 1 8 12) (240 6 8 36) (6000 5 8 12))
             (time-signatures (first (mp:smf-tracks (export-quietly (fixture-score "sc0-carol-6-8"))))))))

(deftest export-tempo-by-hand
  ;; 72 to the quarter, 60 to the dotted quarter, 120 when there is no mark.
  (ok (equal '((0 833333)) (tempos (first (mp:smf-tracks (export-quietly (fixture-score "sc0-pickup")))))))
  (ok (equal '((0 666667)) (tempos (first (mp:smf-tracks (export-quietly (fixture-score "sc0-carol-6-8")))))))
  (ok (equal '((0 500000)) (tempos (first (mp:smf-tracks (export-quietly (fixture-score "sc0-jumps"))))))))

;;; EXPORT-MIDI destinations.

(deftest export-midi-destinations
  (let* ((score (fixture-score "sc0-pickup"))
         (bytes (fixture-octets (export-file "sc0-pickup"))))
    (ok (equalp bytes (quietly (export-midi score nil))))
    (ok (equalp (fixture-octets "sc4-variant-chords-as-markers.mid")
                (quietly (export-midi (fixture-score "sc0-chords-under-rests") nil
                                      :chord-symbols :marker)))
        "keys pass through to SCORE-TO-SMF")
    (stack-pathlib:with-temp-directory (dir)
      (let* ((root (uiop:ensure-directory-pathname (stack-pathlib:path-pathname dir)))
             (file (merge-pathnames "pickup.mid" root))
             (stream-file (merge-pathnames "stream.mid" root)))
        (ok (equal file (quietly (export-midi score file))))
        (ok (equalp bytes (with-open-file (in file :element-type '(unsigned-byte 8))
                            (let ((b (make-array (file-length in) :element-type '(unsigned-byte 8))))
                              (read-sequence b in) b))))
        (with-open-file (out stream-file :direction :output :element-type '(unsigned-byte 8))
          (ok (eq out (quietly (export-midi score out)))))
        (ok (equalp bytes (with-open-file (in stream-file :element-type '(unsigned-byte 8))
                            (let ((b (make-array (file-length in) :element-type '(unsigned-byte 8))))
                              (read-sequence b in) b))))))))

;;; Conditions.

(deftest-parametrize export-argument-errors
    ((label options)
     ("division 0" '(:division 0)) ("division too large" '(:division 32768))
     ("layout" '(:layout :staff)) ("program" '(:program 128))
     ("programs value" '(:programs (("p-7" . 200))))
     ("mix velocity" '(:mix (("v-9" :velocity 300)))) ("mix pan" '(:mix (("v-9" :pan -1))))
     ("mix volume" '(:mix (("v-9" :volume 128))))
     ("unfold" '(:unfold :twice)) ("verse 0" '(:verse 0)) ("verse word" '(:verse :all))
     ("chord symbols" '(:chord-symbols :lyric)) ("accent as default" '(:default-dynamic :sf))
     ("unknown dynamic" '(:default-dynamic :loud)))
  (ok (signals-type (lambda () (apply #'score-to-smf (fixture-score "sc0-pickup") options)) 'type-error)
      label))

(deftest export-not-a-score
  (ok (signals-type (lambda () (score-to-smf :score)) 'type-error)))

(deftest export-unknown-ids
  (let ((score (fixture-score "sc0-keyboard")))
    (let ((c (signalled (lambda () (score-to-smf score :programs '(("nope" . 1)))))))
      (ok (typep c 'sp:unknown-element))
      (ok (equal "nope" (and c (sp:unknown-element-id c)))))
    (let ((c (signalled (lambda () (score-to-smf score :mix '(("e-8" :volume 1)))))))
      (ok (typep c 'sp:unknown-element) "an event id is neither a part nor a voice")
      (ok (equal "e-8" (and c (sp:unknown-element-id c)))))
    (ok (equalp (smf-octets (export-quietly score))
                (smf-octets (handler-bind ((sp:unknown-element #'continue))
                              (export-quietly score :programs '(("nope" . 1))))))
        "CONTINUE ignores the entry")))

(deftest export-invalid-unfold-entry
  (let* ((score (fixture-score "sc0-jumps"))
         (c (signalled (lambda () (score-to-smf score :unfold '(1 99 2))))))
    (ok (typep c 'sp:invalid-position))
    (ok (equal 99 (and c (sp:invalid-position-position c))))
    (ok (typep (signalled (lambda () (score-to-smf score :unfold '((0 . 1))))) 'sp:invalid-position)
        "no pickup: bar 0 is not a bar")
    (ok (equalp (smf-octets (export-quietly score :unfold '(1 2)))
                (smf-octets (handler-bind ((sp:invalid-position #'continue))
                              (export-quietly score :unfold '(1 99 2)))))
        "CONTINUE drops the entry")))

(defun many-voices-score (n)
  (sp:make-score
   :measures (list (sp:make-measure-info :time (mt:parse-meter "4/4") :key (mt:parse-key "C")))
   :parts (list (sp:make-part
                 :staves (list (sp:make-staff))
                 :voices (loop for i below n
                               collect (sp:make-voice
                                        :measures (list (list (sp:make-note-event
                                                               :pitch (mt:parse-pitch "C4")
                                                               :duration 1)))))))))

(deftest export-shared-channels
  (multiple-value-bind (smf losses) (call-quietly (lambda () (score-to-smf (many-voices-score 16))))
    (ok (equal '("ids" "shared channels") losses))
    (ok (= 17 (length (mp:smf-tracks smf))))
    (ok (equal '(0 1 2 3 4 5 6 7 8 10 11 12 13 14 15 0)
               (loop for track in (rest (mp:smf-tracks smf))
                     collect (second (first (tick0-channel-events track))))))
    (ok (equal '("Part 1 1" "Part 1 16")
               (list (track-name (second (mp:smf-tracks smf)))
                     (track-name (car (last (mp:smf-tracks smf))))))))
  (ok (equal '("ids") (losses-of (lambda () (score-to-smf (many-voices-score 15)))))))

(deftest export-pitch-and-tempo-range
  (let ((score (sp:make-score
                :measures (list (sp:make-measure-info
                                 :time (mt:parse-meter "4/4") :key (mt:parse-key "C")
                                 :tempo (list (sp:make-tempo-mark :tempo (mt:make-tempo :bpm 1/2)))))
                :parts (list (sp:make-part
                              :staves (list (sp:make-staff))
                              :voices (list (sp:make-voice
                                             :measures (list (list (sp:make-note-event
                                                                    :pitch (mt:parse-pitch "G#9")
                                                                    :duration 1/2)
                                                                   (sp:make-note-event
                                                                    :pitch (mt:parse-pitch "G9")
                                                                    :duration 1/2))))))))))
    (multiple-value-bind (smf losses) (call-quietly (lambda () (score-to-smf score)))
      (ok (equal '("ids" "pitch range" "tempo range") losses))
      (ok (equal '((960 1920 127 80)) (track-notes (second (mp:smf-tracks smf)))) "G#9 is MIDI 128")
      (ok (equal '((0 16777215)) (tempos (first (mp:smf-tracks smf))))))))

(deftest export-tick-rounding
  ;; Triplet eighths at 100 ticks per quarter fall between ticks.
  (multiple-value-bind (smf losses)
      (call-quietly (lambda () (score-to-smf (fixture-score "sc0-keyboard") :division 100)))
    (ok (equal '("ids" "grace notes" "tick rounding") losses))
    (ok (equal '((500 533 77 49) (533 567 79 49) (567 600 81 49))
               (subseq (track-notes (second (mp:smf-tracks smf))) 1 4))
        "floor(400 x + 1/2) of 5/4, 4/3, 17/12 and 3/2")))
