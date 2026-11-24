;;;; SC4 SMF-TO-SCORE and IMPORT-MIDI (src/tracks.lisp, measures.lisp,
;;;; import.lisp). The round trip reads the golden exports back: the brief's
;;;; "export -> import equals the source in pitches, onsets and lyrics for
;;;; quantised content", here with ends, spellings in the key, the measure map,
;;;; chord symbols and titles too, against the export facts (music21 for what
;;;; sounds). The other files were written by generate-sc4.py with mido; their
;;;; notes are in sc4-import-facts.sexp, the rest of the expectations are by hand.

(in-package #:score-backend-midi/tests)

(defparameter *import-facts* (fixture-form "sc4-import-facts.sexp"))

(defun import-facts (file) (rest (assoc file *import-facts* :test #'string=)))

(defun whole-notes (rows)
  "Fact rows (start end key ...) in whole notes as (start end key)."
  (mapcar (lambda (r) (subseq r 0 3)) rows))

(defun tick-rows (rows)
  "Export fact notes (on off key velocity) as (onset end key) in whole notes."
  (mapcar (lambda (r) (list (ticks->whole (first r) 480) (ticks->whole (second r) 480) (third r)))
          rows))

(defun dehyphen (text)
  (if (and (plusp (length text)) (char= #\- (char text (1- (length text)))))
      (subseq text 0 (1- (length text)))
      text))

(defun distinct-labels (labels)
  (loop for (a b) on labels unless (equal a b) collect a))

(defvar *round-trips* (make-hash-table :test 'equal))

(defun round-trip (name)
  "(score guesses) of importing the golden export of fixture NAME."
  (or (gethash name *round-trips*)
      (setf (gethash name *round-trips*)
            (multiple-value-list
             (guesses-of (lambda () (import-midi (fixture-octets (export-file name)))))))))

;;; Round trip ---------------------------------------------------------------------

(deftest-parametrize round-trip-valid
    ((name) :rows +export-fixtures+)
  (let ((score (first (round-trip name))))
    (ok (typep score 'sp:score))
    (ok (null (sp:check-score score)) "no CHECK-SCORE issue")
    (ok (minted-ids-p score) "ids minted in document order")
    (ok (every #'midi-provenance-p (sp:score-elements score)) "provenance :midi everywhere")
    (ok (sp:score-equal score (import-quietly (fixture-octets (export-file name)))) "deterministic")))

(deftest-parametrize round-trip-sounding-notes
    ((name) :rows +export-fixtures+)
  (let* ((score (first (round-trip name)))
         (voices (score-voices score))
         (rows (facts-voices name)))
    (ok (= (length rows) (length voices)) "one voice per exported voice")
    (ok (null (loop for row in rows
                    for voice in voices
                    unless (equal (tick-rows (sixth row)) (voice-sounding score voice))
                      collect (first row)))
        "onsets, ends and keys of every voice")))

(deftest-parametrize round-trip-spelling-in-key
    ((name) :rows +export-fixtures+)
  ;; Notes in the key (MT4's rule S1) come back as written.
  (let* ((score (first (round-trip name)))
         (bad '()))
    (loop for row in (facts-voices name)
          for voice in (score-voices score)
          for starts = (voice-starts score voice)
          do (loop for (on key pitch in-key) in (eighth row)
                   for found = (find-if (lambda (s) (and (= (first s) (ticks->whole on 480))
                                                         (= (second s) key)))
                                        starts)
                   when (and in-key (not (equal pitch (third found))))
                     do (push (list (first row) on pitch (third found)) bad)))
    (ok (null bad) (report bad))))

(deftest-parametrize round-trip-lyrics
    ((name) :rows +export-fixtures+)
  (let ((score (first (round-trip name))))
    (ok (null (loop for row in (facts-voices name)
                    for voice in (score-voices score)
                    unless (equal (mapcar (lambda (l) (list (ticks->whole (first l) 480)
                                                            (dehyphen (second l)) (third l)))
                                          (seventh row))
                                  (voice-lyrics score voice))
                      collect (first row)))
        "onset, text and syllabic of every syllable")))

(deftest-parametrize round-trip-measure-map
    ((name) :rows +export-fixtures+)
  (let ((score (first (round-trip name))))
    (ok (equal (facts name :measures) (measure-rows score)))
    (ok (eq :final (sp:measure-info-barline (fset:last (sp:score-measure-map score)))))))

(deftest-parametrize round-trip-parts-and-text
    ((name) :rows +export-fixtures+)
  (let* ((score (first (round-trip name)))
         (source (fixture-score name)))
    (ok (equal (distinct-labels (mapcar #'third (facts-voices name))) (part-names score)))
    (ok (equal (getf (sp:score-metadata source) :title) (getf (sp:score-metadata score) :title)))
    (ok (equal (loop for (tick text) in (facts name :chords)
                     collect (let ((position (sp:offset-position score (ticks->whole tick 480))))
                               (list (car position) (cdr position) (subseq text 6) nil)))
               (anchor-rows score))
        "prefixed chord text comes back exact")))

(deftest-parametrize round-trip-guesses
    ((name) :rows +export-fixtures+)
  ;; Exported content is on the grid and in its signatures: the only guesses
  ;; are spellings of notes outside the key.
  (destructuring-bind (score guesses) (round-trip name)
    (ok (equal (mapcar #'first guesses) (mapcar #'sp:element-id (sp:uncertain-elements score))))
    (ok (every (lambda (g) (equal "spelling" (second g))) guesses))
    (ok (every (lambda (e) (typep e '(or sp:note-event sp:chord-note))) (sp:uncertain-elements score)))))

(deftest round-trip-part-layout
  (let* ((score (import-quietly (fixture-octets "sc4-variant-satb-part-layout.mid")))
         (parts (seq-list (sp:score-parts score))))
    (ok (= 1 (length parts)))
    (ok (equal "Choir" (sp:part-name (first parts))))
    (ok (equal '(nil nil nil nil) (mapcar #'sp:voice-name (sp:part-voices (first parts)))))
    (ok (equal (mapcar (lambda (row) (tick-rows (sixth row))) (facts-voices "sc0-satb"))
               (mapcar (lambda (v) (voice-sounding score v)) (score-voices score))))))

(deftest round-trip-voice-names
  ;; One staff per voice; the tenor's mean key is 61, so treble.
  (let ((score (first (round-trip "sc0-satb"))))
    (ok (equal '("Soprano" "Alto" "Tenor" "Bass") (mapcar #'sp:voice-name (score-voices score))))
    (ok (equal '(:treble :treble :treble :bass)
               (mapcar #'sp:staff-clef (sp:part-staves (fset:first (sp:score-parts score))))))
    (ok (equal '(1 2 3 4) (mapcar #'sp:voice-staff (score-voices score))))))

(deftest round-trip-as-written
  (let ((score (import-quietly (fixture-octets "sc4-variant-voltas-as-written.mid"))))
    (ok (= 8 (fset:size (sp:score-measure-map score))))))

(deftest round-trip-tuplets-and-ties
  ;; sc4-rhythms imports with the source's triplets, sextuplets and tie.
  (let* ((score (first (round-trip "sc4-rhythms")))
         (events (mapcar #'second (voice-events score (first (score-voices score))))))
    (ok (equal (mapcar #'sp:event-tuplet
                       (mapcar #'second (voice-events (fixture-score "sc4-rhythms")
                                                      (first (score-voices (fixture-score "sc4-rhythms"))))))
               (mapcar #'sp:event-tuplet events)))
    (ok (equal (mapcar #'sp:event-duration
                       (mapcar #'second (voice-events (fixture-score "sc4-rhythms")
                                                      (first (score-voices (fixture-score "sc4-rhythms"))))))
               (mapcar #'sp:event-duration events)))))

;;; Meta events, hints ------------------------------------------------------------

(defparameter +meta-measures+
  '((1/4 "3/4" "D major" t ((0 90 1/4)) nil)
    (nil nil nil nil () "A")
    (nil nil nil nil () nil)
    (nil nil "D minor" nil () nil)
    (nil "6/8" nil nil ((1/8 40 3/8)) "B")
    (3/8 nil nil nil () nil))
  "By hand from sc4-meta.mid: a 1/4 pickup before 3/4, D major then D minor at
bar 3, 6/8 at bar 4 with 40 dotted quarters an eighth in, a 3/8 final bar.")

(deftest import-meta-events
  (multiple-value-bind (score guesses) (guesses-of (lambda () (import-midi (fixture-octets "sc4-meta.mid"))))
    (ok (equal +meta-measures+ (measure-rows score)))
    (ok (equal '(:title "Meta Test" :copyright "(c) Nobody") (sp:score-metadata score)))
    (ok (equal '((1 0 "D" nil) (1 1/4 "G" 1/2) (2 0 "A7" nil)) (anchor-rows score))
        "prefixed text and marker exact, plain \"G\" guessed, \"Intro\" no chord")
    (ok (equal (whole-notes (getf (import-facts "sc4-meta.mid") :melody))
               (voice-sounding score (first (score-voices score)))))
    (ok (equal '("A4" "D5" "C#5" "B4" "A4" "F4" "A4" "G4" "F4")
               (mapcar #'third (voice-starts score (first (score-voices score))))))
    (ok (equal (list (list (sp:element-id (fset:@ (sp:score-chord-symbols score) 1)) "chord symbol" 1/2))
               guesses))
    (ok (null (sp:check-score score)))))

(deftest import-chord-symbol-options
  (ok (equal '((1 0 "D" nil) (2 0 "A7" nil))
             (anchor-rows (import-quietly (fixture-octets "sc4-meta.mid") :chord-symbols :exact))))
  (ok (null (anchor-rows (import-quietly (fixture-octets "sc4-meta.mid") :chord-symbols nil)))))

(deftest import-hints-that-disagree
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (import-midi (fixture-octets "sc4-meta.mid")
                                          :meter (mt:parse-meter "3/4")
                                          :tempo (mt:make-tempo :bpm 100 :beat-unit 1/4)
                                          :key (mt:parse-key "D"))))
    (let ((m0 (fset:first (sp:score-measure-map score))))
      (ok (equal '(1/4 "3/4" "D major" t ((0 100 1/4)) nil) (first (measure-rows score))))
      (ok (eql 1/2 (sp:element-confidence m0)) "3/4 against the file's 1/4")
      (ok (eql 1/2 (sp:element-confidence (first (sp:measure-info-tempo m0)))))
      (ok (equal (list (list (sp:element-id m0) "meter" 1/2)
                       (list (sp:element-id (first (sp:measure-info-tempo m0))) "tempo" 1/2))
                 (remove "chord symbol" guesses :key #'second :test #'equal))))))

(deftest import-hints-that-agree
  (let* ((score (import-quietly (fixture-octets "sc4-meta.mid") :meter (mt:parse-meter "1/4")
                                :tempo (mt:make-tempo :bpm 90 :beat-unit 1/4) :key (mt:parse-key "D")))
         (m0 (fset:first (sp:score-measure-map score))))
    (ok (null (sp:element-confidence m0)))
    (ok (null (sp:element-confidence (first (sp:measure-info-tempo m0)))))))

(deftest import-no-time-signature
  ;; sc4-spell-g-flat.mid has neither a time nor a key signature.
  (let* ((score (import-quietly (fixture-octets "sc4-spell-g-flat.mid") :key (mt:parse-key "Gb")))
         (m0 (fset:first (sp:score-measure-map score))))
    (ok (equal "4/4" (mt:meter-string (sp:measure-info-time m0))) "4/4 assumed")
    (ok (eql 1/2 (sp:element-confidence m0)))
    (ok (= 4 (fset:size (sp:score-measure-map score))))
    (let ((hinted (import-quietly (fixture-octets "sc4-spell-g-flat.mid") :key (mt:parse-key "Gb")
                                  :meter (mt:parse-meter "2/4"))))
      (ok (= 8 (fset:size (sp:score-measure-map hinted))))
      (ok (null (sp:element-confidence (fset:first (sp:score-measure-map hinted))))
          "a hint with no event to disagree with"))))

;;; Tracks, parts, the melody ------------------------------------------------------

(deftest import-ensemble-parts
  (multiple-value-bind (score losses)
      (call-quietly (lambda () (import-midi (fixture-octets "sc4-ensemble.mid"))))
    (let ((facts (import-facts "sc4-ensemble.mid"))
          (voices (score-voices score)))
      (ok (equal '("percussion") losses))
      (ok (equal '("Piano" "Flute" "Bass") (part-names score)))
      (ok (equal (list (getf facts :piano) (getf facts :flute) (getf facts :bass))
                 (mapcar (lambda (v) (voice-sounding score v)) voices)))
      (ok (equal '(:bass :treble :bass)
                 (loop for part in (seq-list (sp:score-parts score))
                       collect (sp:staff-clef (first (sp:part-staves part))))))
      (ok (equal '((0 "Here" :begin) (1/4 "we" :end) (1/2 "go" :single)) (voice-lyrics score (second voices)))
          "lyrics of a track without notes go to the melody")
      (ok (= 2 (count-if (lambda (p) (sp:note-tie (seventh p))) (voice-pieces score (first voices))))
          "F3 and A3 held under the moving top voice are tied")
      (ok (null (sp:check-score score))))))

(deftest import-ensemble-voices
  (let ((smf (mp:read-smf (fixture-octets "sc4-ensemble.mid"))))
    (ok (equal '((1 . 0) (2 . 1) (3 . 2)) (source-voices smf)))
    (ok (equal '((2 . 1) 2) (multiple-value-list (melody-voice smf))))
    (ok (null (melody-voice (mp:make-smf :tracks '()))))
    (ok (equal '((0 . 0) (0 . 1) (0 . 2)) (source-voices (mp:read-smf (fixture-octets "sc4-ensemble-format0.mid")))))))

(deftest import-melody-only
  (multiple-value-bind (score guesses)
      (guesses-of (lambda () (import-midi (fixture-octets "sc4-ensemble.mid") :parts :melody)))
    (let ((part (fset:first (sp:score-parts score))))
      (ok (equal '("Flute") (part-names score)))
      (ok (eql 1/2 (sp:element-confidence part)) "two monophonic lines to choose from")
      (ok (equal (list (list (sp:element-id part) "melody" 1/2)) guesses))))
  (let ((score (import-quietly (fixture-octets "sc4-ensemble.mid") :parts :melody :melody 3)))
    (ok (equal '("Bass") (part-names score)))
    (ok (null (sp:element-confidence (fset:first (sp:score-parts score)))) "given, not guessed"))
  (ok (equal '("Bass" "Piano")
             (part-names (import-quietly (fixture-octets "sc4-ensemble.mid") :parts '(3 (1 . 0) (4 . 9)))))
      "selections in order; percussion is no source voice"))

(deftest import-format-0
  (let* ((score (import-quietly (fixture-octets "sc4-ensemble-format0.mid")))
         (voices (score-voices score))
         (facts (import-facts "sc4-ensemble.mid")))
    (ok (equal '("Piano") (part-names score)) "one track, one part, its first instrument name")
    (ok (equal '(nil nil nil) (mapcar #'sp:voice-name voices)))
    (ok (equal (list (getf facts :piano) (getf facts :flute) (getf facts :bass))
               (mapcar (lambda (v) (voice-sounding score v)) voices)))
    (ok (equal '((0 "Here" :begin) (1/4 "we" :end) (1/2 "go" :single)) (voice-lyrics score (second voices)))
        "a track of several voices sends its lyrics to the melody")))

(deftest import-instrument-groups
  (let* ((score (import-quietly (fixture-octets "sc4-strings.mid")))
         (parts (seq-list (sp:score-parts score))))
    (ok (equal '("Violins" "Viola" "Cello") (part-names score)))
    (ok (equal '(("Violin I" "Violin II") (nil) (nil))
               (mapcar (lambda (p) (mapcar #'sp:voice-name (sp:part-voices p))) parts)))
    (ok (equal '((:treble :treble) (:treble) (:bass))
               (mapcar (lambda (p) (mapcar #'sp:staff-clef (sp:part-staves p))) parts)))
    (ok (equal '((1 2) (1) (1))
               (mapcar (lambda (p) (mapcar #'sp:voice-staff (sp:part-voices p))) parts)))))

;;; Lyrics -----------------------------------------------------------------------

(deftest import-lyric-events
  (multiple-value-bind (score losses)
      (call-quietly (lambda () (import-midi (fixture-octets "sc4-lyrics.mid"))))
    (let ((voice (first (score-voices score))))
      (ok (equal '("lyrics") losses) "\"sweet\" lands on the note \"how\" holds")
      (ok (equal '((0 "A" :begin) (1/4 "maz" :middle) (3/4 "ing" :end) (7/8 "grace" :single)
                   (1 "how" :single) (3/2 "the" :single))
                 (voice-lyrics score voice)))
      (ok (equal '(1 1/2 1 1 1 1)
                 (loop for (nil e) in (voice-events score voice)
                       append (mapcar #'sp:element-confidence (sp:event-lyrics e))))
          "a lyric five ticks early is a guess"))))

(deftest import-karaoke
  (let* ((score (import-quietly (fixture-octets "sc4-karaoke.mid")))
         (voice (first (score-voices score))))
    (ok (equal "Twinkle, Twinkle" (getf (sp:score-metadata score) :title)))
    (ok (equal '("Melody") (part-names score)) "the Words track has no notes, so no part")
    (ok (equal '(("Twin" :begin) ("kle" :end) ("twin" :begin) ("kle" :end) ("lit" :begin) ("tle" :end)
                 ("star," :single) ("How" :single) ("I" :single) ("won" :begin) ("der" :end)
                 ("what" :single) ("you" :single) ("are" :single))
               (mapcar #'rest (voice-lyrics score voice))))
    (ok (zerop (fset:size (sp:score-chord-symbols score))) "karaoke text is never a chord guess")))

(deftest import-without-lyrics
  (let ((score (import-quietly (fixture-octets "sc4-lyrics.mid") :lyrics nil)))
    (ok (null (voice-lyrics score (first (score-voices score)))))
    (ok (null (losses-of (lambda () (import-midi (fixture-octets "sc4-lyrics.mid") :lyrics nil))))
        "no lyric, so none dropped")))

;;; Sources and conditions ---------------------------------------------------------

(deftest import-sources
  (let ((bytes (fixture-octets "sc4-meta.mid"))
        (expected (import-quietly (fixture-octets "sc4-meta.mid"))))
    (ok (sp:score-equal expected (import-quietly (fixture-path "sc4-meta.mid"))) "a pathname")
    (ok (sp:score-equal expected (import-quietly (namestring (fixture-path "sc4-meta.mid")))) "a string")
    (ok (sp:score-equal expected (with-open-file (in (fixture-path "sc4-meta.mid")
                                                     :element-type '(unsigned-byte 8))
                                   (import-quietly in)))
        "a stream")
    (ok (sp:score-equal expected (import-quietly (mp:read-smf bytes))) "an SMF")))

(deftest import-truncated-file
  (let* ((bytes (fixture-octets "sc4-lyrics.mid"))
         (cut (subseq bytes 0 (- (length bytes) 12)))
         (c (signalled (lambda () (import-midi cut)))))
    (ok (typep c 'sp:score-format-error))
    (ok (eq :midi (and c (sp:score-format-error-format c))))
    (ok (typep (and c (sp:score-format-error-cause c)) 'mp:midi-parse-error))
    (ok (eql (and c (mp:midi-parse-error-offset (sp:score-format-error-cause c)))
             (and c (sp:score-format-error-position c))))
    (let ((partial (handler-bind ((sp:score-format-error (lambda (c) (declare (ignore c))
                                                           (mp:use-partial-smf))))
                     (import-quietly cut)))
          (full (import-quietly bytes)))
      (ok (typep partial 'sp:score) "USE-PARTIAL-SMF from a SCORE-FORMAT-ERROR handler")
      (ok (equal (subseq (voice-sounding full (first (score-voices full))) 0 4)
                 (subseq (voice-sounding partial (first (score-voices partial))) 0 4))))))

(deftest import-smpte-division
  (let ((smf (mp:make-smf :format 1 :division (mp:make-smpte-division :frames-per-second 25
                                                                      :ticks-per-frame 40)
                          :tracks (list (list (mp:make-note-on-event :key 60 :velocity 90)
                                              (mp:make-note-off-event :delta 1920 :key 60))))))
    (let ((c (signalled (lambda () (smf-to-score smf)))))
      (ok (typep c 'sp:score-format-error))
      (ok (equal "SMPTE division" (and c (sp:score-error-reason c)))))
    (let ((score (handler-bind ((sp:score-format-error (lambda (c) (use-value 480 c))))
                   (import-quietly smf))))
      (ok (equal '((0 1 60)) (voice-sounding score (first (score-voices score))))
          "USE-VALUE 480: 1920 ticks are a whole note"))))

(deftest-parametrize import-argument-errors
    ((label thunk)
     ("not an SMF" (lambda () (smf-to-score :smf)))
     ("quantize" (lambda () (import-midi (fixture-octets "sc4-meta.mid") :quantize :maybe)))
     ("parts" (lambda () (import-midi (fixture-octets "sc4-meta.mid") :parts :some)))
     ("melody names no voice" (lambda () (import-midi (fixture-octets "sc4-meta.mid") :melody 42)))
     ("key as text" (lambda () (import-midi (fixture-octets "sc4-meta.mid") :key "D")))
     ("meter as text" (lambda () (import-midi (fixture-octets "sc4-meta.mid") :meter "3/4")))
     ("chord symbols" (lambda () (import-midi (fixture-octets "sc4-meta.mid") :chord-symbols :fuzzy)))
     ("subdivisions" (lambda () (import-midi (fixture-octets "sc4-meta.mid") :subdivisions '(5)))))
  (ok (signals-type thunk 'type-error) label))

(deftest import-empty-smf
  (let ((score (import-quietly (mp:make-smf :tracks (list (list (mp:make-end-of-track-event)))))))
    (ok (zerop (fset:size (sp:score-measure-map score))))
    (ok (zerop (fset:size (sp:score-parts score))))))
