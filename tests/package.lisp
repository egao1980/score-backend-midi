;;;; Test helpers for the SC4 suite. The expected values come from
;;;; tests/fixtures (generate-sc4.py: music21 for what sounds when, mido for the
;;;; bytes; PROVENANCE.md) and from hand-written rows. The helpers here read
;;;; SMFs and scores with their own code, never with the implementation's.

(defpackage #:score-backend-midi/tests
  (:use #:cl #:rove #:score-backend-midi)
  (:local-nicknames (#:sp #:score-protocol) (#:mp #:midi-protocol)
                    (#:mt #:music-theory) (#:sat #:sat-protocol)))

(in-package #:score-backend-midi/tests)

;;; Fixtures -------------------------------------------------------------------

(defun fixture-path (name)
  (asdf:system-relative-pathname "score-backend-midi/tests"
                                 (format nil "tests/fixtures/~A" name)))

(defun fixture-octets (name)
  (with-open-file (in (fixture-path name) :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence bytes in)
      bytes)))

(defun fixture-form (name)
  "The single top-level form in tests/fixtures/NAME."
  (with-open-file (in (fixture-path name) :external-format :utf-8)
    (with-standard-io-syntax
      (let ((*read-eval* nil)
            (*package* (find-package '#:score-backend-midi/tests)))
        (read in)))))

(defvar *scores* (make-hash-table :test 'equal))

(defun fixture-score (name)
  "The fixture score NAME (tests/fixtures/NAME.sexp), read once."
  (or (gethash name *scores*)
      (setf (gethash name *scores*)
            (sp:sexp-to-score (fixture-form (format nil "~A.sexp" name))))))

(defparameter +export-fixtures+
  '("sc0-carol-6-8" "sc0-chords-under-rests" "sc0-jumps" "sc0-key-change" "sc0-keyboard"
    "sc0-omr-result" "sc0-pickup" "sc0-repeats-voltas" "sc0-satb" "sc0-three-verses"
    "sc4-dynamics" "sc4-rhythms" "sc4-strophic")
  "The fixture scores exported with default options (sc4-export-*.mid).")

(defun export-file (name)
  (format nil "sc4-export-~A.mid" (subseq name 4)))

(defparameter *facts* (fixture-form "sc4-export-facts.sexp"))

(defun facts (name key)
  (getf (rest (or (assoc name *facts* :test #'string=) (error "no facts for ~A" name))) key))

(defun facts-voices (name)
  "(id track-name part-label channel program notes lyrics spellings) per voice."
  (facts name :voices))

;;; Conditions -----------------------------------------------------------------

(defun call-quietly (thunk)
  "(values result losses): THUNK's value, and the WHAT of every LOSSY-CONVERSION
it warned, in order, each muffled."
  (let ((losses '()))
    (values (handler-bind ((sp:lossy-conversion
                             (lambda (w)
                               (push (sp:lossy-conversion-what w) losses)
                               (muffle-warning w))))
              (funcall thunk))
            (nreverse losses))))

(defmacro quietly (&body body)
  `(values (call-quietly (lambda () ,@body))))

(defun losses-of (thunk)
  (nth-value 1 (call-quietly thunk)))

(defun lossy-formats (thunk)
  "The FORMAT of every LOSSY-CONVERSION THUNK warns."
  (let ((formats '()))
    (handler-bind ((sp:lossy-conversion
                     (lambda (w) (push (sp:lossy-conversion-format w) formats) (muffle-warning w))))
      (funcall thunk))
    formats))

(defun signalled (thunk)
  "The ERROR THUNK signals (warnings muffled), or NIL when it returns."
  (handler-case (progn (call-quietly thunk) nil)
    (error (c) c)))

(defun signals-type (thunk type)
  (typep (signalled thunk) type))

(defun guesses-of (thunk)
  "(values result guesses): THUNK's value and every LOW-CONFIDENCE-GUESS it
signalled, as (id what confidence), in order. Lossy warnings are muffled."
  (let ((guesses '()))
    (values (handler-bind ((sp:low-confidence-guess
                             (lambda (g)
                               (push (list (sp:low-confidence-guess-element-id g)
                                           (sp:low-confidence-guess-what g)
                                           (sp:low-confidence-guess-confidence g))
                                     guesses))))
              (call-quietly thunk))
            (nreverse guesses))))

(defun export-quietly (score &rest keys)
  (quietly (apply #'score-to-smf score keys)))

(defun import-quietly (source &rest keys)
  (quietly (apply (if (typep source 'mp:smf) #'smf-to-score #'import-midi) source keys)))

(defun report (bad)
  (format nil "~D mismatches~@[, first: ~S~]" (length bad)
          (and bad (subseq bad 0 (min 6 (length bad))))))

;;; Reading SMFs -----------------------------------------------------------------

(defun smf-octets (smf)
  (mp:write-smf smf nil))

(defun timed-of (track predicate)
  "(tick . event) for the events of TRACK that satisfy PREDICATE, in order."
  (remove-if-not predicate (mp:track-to-absolute track) :key #'cdr))

(defun note-on-p (e) (and (mp:note-on-event-p e) (plusp (mp:note-on-event-velocity e))))

(defun note-off-p (e)
  (or (mp:note-off-event-p e) (and (mp:note-on-event-p e) (zerop (mp:note-on-event-velocity e)))))

(defun event-key (e)
  (if (mp:note-on-event-p e) (mp:note-on-event-key e) (mp:note-off-event-key e)))

(defun track-notes (track &key channel)
  "((on off key velocity) ...) of TRACK, sorted by on then key: each note-on
paired with the first later note-off of its channel and key not yet used."
  (let ((open (make-hash-table :test 'equal)) (out '()))
    (loop for (tick . e) in (mp:track-to-absolute track)
          when (and (or (note-on-p e) (note-off-p e))
                    (or (null channel) (= channel (mp:channel-event-channel e))))
            do (let ((k (cons (mp:channel-event-channel e) (event-key e))))
                 (if (note-on-p e)
                     (setf (gethash k open) (append (gethash k open)
                                                    (list (list tick (mp:note-on-event-velocity e)))))
                     (let ((start (pop (gethash k open))))
                       (when start
                         (push (list (first start) tick (cdr k) (second start)) out))))))
    (sort out (lambda (a b) (or (< (first a) (first b))
                                (and (= (first a) (first b)) (< (third a) (third b))))))))

(defun track-texts (track predicate)
  "((tick text) ...) of the text meta events of TRACK satisfying PREDICATE."
  (mapcar (lambda (te) (list (car te) (mp:text-meta-event-text (cdr te))))
          (timed-of track predicate)))

(defun track-name (track)
  (second (first (track-texts track #'mp:track-name-event-p))))

(defun instrument-name (track)
  (second (first (track-texts track #'mp:instrument-name-event-p))))

(defun track-end (track)
  (car (first (last (mp:track-to-absolute track)))))

(defun tick0-channel-events (track)
  "(kind channel value) for the program changes and controllers at tick 0."
  (loop for (tick . e) in (mp:track-to-absolute track)
        while (zerop tick)
        when (mp:program-change-event-p e)
          collect (list :program (mp:channel-event-channel e) (mp:program-change-event-program e))
        when (mp:control-change-event-p e)
          collect (list (mp:control-change-event-controller e) (mp:channel-event-channel e)
                        (mp:control-change-event-value e))))

(defun time-signatures (track)
  (mapcar (lambda (te)
            (let ((e (cdr te)))
              (list (car te) (mp:time-signature-event-numerator e)
                    (mp:time-signature-event-denominator e)
                    (mp:time-signature-event-clocks-per-click e))))
          (timed-of track #'mp:time-signature-event-p)))

(defun key-signatures (track)
  (mapcar (lambda (te)
            (list (car te) (mp:key-signature-event-sharps (cdr te))
                  (mp:key-signature-event-minor-p (cdr te))))
          (timed-of track #'mp:key-signature-event-p)))

(defun tempos (track)
  (mapcar (lambda (te) (list (car te) (mp:tempo-event-tempo (cdr te))))
          (timed-of track #'mp:tempo-event-p)))

;;; Reading scores ---------------------------------------------------------------

(defun seq-list (seq) (fset:convert 'list seq))

(defun score-voices (score)
  "Every voice of SCORE in document order."
  (loop for part in (seq-list (sp:score-parts score)) append (sp:part-voices part)))

(defun voice-events (score voice)
  "(onset event bar) for every event of VOICE, onsets absolute (whole notes)."
  (loop for measure in (seq-list (sp:voice-measures voice))
        for bar from (sp:score-first-bar score)
        append (loop with offset = 0
                     for e in (seq-list measure)
                     collect (list (+ (sp:bar-start score bar) offset) e bar)
                     unless (and (typep e 'sp:sounding-event) (sp:event-grace e))
                       do (incf offset (sp:event-duration e)))))

(defun event-notes (e)
  (typecase e
    (sp:note-event (list e))
    (sp:chord-event (sp:chord-event-notes e))
    (t '())))

(defun voice-pieces (score voice)
  "(id onset end key pitch event) for every note and chord note of VOICE."
  (loop for (onset e) in (voice-events score voice)
        unless (or (typep e 'sp:rest-event) (sp:event-grace e))
          append (loop for n in (event-notes e)
                       collect (list (sp:element-id n) onset (+ onset (sp:event-duration e))
                                     (mt:pitch-midi (sp:note-pitch n)) (sp:note-pitch n) e n))))

(defun voice-sounding (score voice)
  "((onset end key) ...) of VOICE with tied pieces joined, sorted by onset then key."
  (let* ((pieces (voice-pieces score voice))
         (by-id (make-hash-table :test 'equal))
         (targets (make-hash-table :test 'equal)))
    (dolist (p pieces) (setf (gethash (first p) by-id) p))
    (dolist (p pieces)
      (let ((tie (sp:note-tie (seventh p))))
        (when tie (setf (gethash (sp:tie-end tie) targets) t))))
    (sort (loop for p in pieces
                unless (gethash (first p) targets)
                  collect (let ((end (third p)) (cur p))
                            (loop for tie = (sp:note-tie (seventh cur))
                                  while tie
                                  do (setf cur (gethash (sp:tie-end tie) by-id)
                                           end (third cur)))
                            (list (second p) end (fourth p))))
          (lambda (a b) (or (< (first a) (first b))
                            (and (= (first a) (first b)) (< (third a) (third b))))))))

(defun voice-starts (score voice)
  "((onset key pitch-name note) ...) of the first piece of every sounding note."
  (let ((targets (make-hash-table :test 'equal)) (pieces (voice-pieces score voice)))
    (dolist (p pieces)
      (let ((tie (sp:note-tie (seventh p))))
        (when tie (setf (gethash (sp:tie-end tie) targets) t))))
    (loop for p in pieces
          unless (gethash (first p) targets)
            collect (list (second p) (fourth p) (mt:pitch-name (fifth p)) (seventh p) (sixth p)))))

(defun voice-lyrics (score voice)
  "((onset text syllabic) ...) of the lyrics of VOICE, verse 1."
  (loop for (onset e) in (voice-events score voice)
        append (loop for l in (sp:event-lyrics e)
                     when (= 1 (sp:lyric-verse l))
                       collect (list onset (sp:lyric-text l) (sp:lyric-syllabic l)))))

(defun measure-rows (score)
  "(length time key pickup tempo-marks rehearsal) per measure, as the facts
write them: TIME a meter string, KEY a key name, tempo marks (offset bpm unit)."
  (loop for m in (seq-list (sp:score-measure-map score))
        collect (list (sp:measure-info-length m)
                      (and (sp:measure-info-time m) (mt:meter-string (sp:measure-info-time m)))
                      (and (sp:measure-info-key m) (mt:key-name (sp:measure-info-key m)))
                      (sp:measure-info-pickup-p m)
                      (loop for tm in (sp:measure-info-tempo m)
                            for tempo = (sp:tempo-mark-tempo tm)
                            when tempo
                              collect (list (sp:tempo-mark-offset tm) (mt:tempo-bpm tempo)
                                            (mt:tempo-beat-unit tempo)))
                      (and (sp:measure-info-rehearsal m)
                           (sp:rehearsal-mark-text (sp:measure-info-rehearsal m))))))

(defun anchor-rows (score)
  "(bar offset text confidence) per chord-symbol anchor, text in :POP."
  (loop for a in (seq-list (sp:score-chord-symbols score))
        collect (list (car (sp:anchor-position a)) (cdr (sp:anchor-position a))
                      (mt:print-chord-symbol (sp:anchor-symbol a) :dialect :pop)
                      (sp:element-confidence a))))

(defun part-names (score)
  (mapcar #'sp:part-name (seq-list (sp:score-parts score))))

(defun unfold-rows (score)
  "(source-bar . pass) for each measure of (score-protocol:unfold SCORE)."
  (multiple-value-bind (view id-map passes) (sp:unfold score)
    (let ((source-ids (mapcar #'sp:element-id (seq-list (sp:score-measure-map score)))))
      (loop for m in (seq-list (sp:score-measure-map view))
            collect (cons (+ (sp:score-first-bar score)
                             (position (fset:lookup id-map (sp:element-id m)) source-ids :test #'equal))
                          (fset:lookup passes (sp:element-id m)))))))

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

(defun ticks->whole (tick division) (/ tick (* 4 division)))

(defun minted-prefix (element)
  "The prefix score-protocol gives ELEMENT's minted ids, decided here."
  (etypecase element
    (sp:measure-info "m") (sp:part "p") (sp:staff "st") (sp:voice "v") (sp:event "e")
    (sp:chord-note "n") (sp:lyric "ly") (sp:dynamic-mark "dy") (sp:fermata "fe")
    (sp:breath-mark "br") (sp:articulation "ar") (sp:tie "ti") (sp:tempo-mark "tm")
    (sp:rehearsal-mark "rh") (sp:jump-mark "jm") (sp:ending "en")
    (sp:chord-symbol-anchor "h") (sp:spanner "sp")))

(defun minted-ids-p (score)
  "True when every element's id is its prefix and its 1-based place in document
order in base 36, and the counter is the number of elements."
  (let ((elements (sp:score-elements score)))
    (and (= (length elements) (sp:score-id-counter score))
         (loop for e in elements
               for i from 1
               always (string= (sp:element-id e)
                               (format nil "~A-~(~36R~)" (minted-prefix e) i))))))

(defun midi-provenance-p (element)
  (let ((p (sp:element-provenance element)))
    (and p (eq :midi (sp:provenance-source p))
         (equal "score-backend-midi" (sp:provenance-backend p)))))

(defun uv-available-p ()
  (handler-case (zerop (stack-process:run '("uv" "--version") :output nil :error-output nil
                                                              :timeout 60))
    (error () nil)))
