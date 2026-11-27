;;;; SC6 (0.2.0) NOTES-TO-SCORE (src/notes.lisp). The takes are tempo-test.lisp's
;;;; renderings of the ten sc4-performances.sexp melodies (its header), plus
;;;; hand rows. Expectations come from the notation (the round trips), from
;;;; music-theory on the notation (keys: MT5's in-tune fit is MT4's DETECT-KEY of
;;;; the duration-weighted histogram), from hand arithmetic on the file header,
;;;; and, for the calibrated counts, from a reference implementation of the
;;;; rules (exact arithmetic: any implementation of the rules reproduces them).
;;;; The SMF tests in the other files pin the code NOTES-TO-SCORE shares with
;;;; SMF-TO-SCORE (moved, not changed, in 0.2.0).

(in-package #:score-backend-midi/tests)

;;; Helpers ---------------------------------------------------------------------------

(defun run-notes (events &rest keys)
  "(values score fit guesses losses): NOTES-TO-SCORE of EVENTS with KEYS; every
LOW-CONFIDENCE-GUESS as (id what confidence), and every LOSSY-CONVERSION as
(what format direction), muffled, in order."
  (let ((guesses '()) (losses '()) score fit)
    (handler-bind ((sp:lossy-conversion
                     (lambda (w)
                       (push (list (sp:lossy-conversion-what w) (sp:lossy-conversion-format w)
                                   (sp:lossy-conversion-direction w))
                             losses)
                       (muffle-warning w)))
                   (sp:low-confidence-guess
                     (lambda (g)
                       (push (list (sp:low-confidence-guess-element-id g)
                                   (sp:low-confidence-guess-what g)
                                   (sp:low-confidence-guess-confidence g))
                             guesses))))
      (setf (values score fit) (apply #'notes-to-score events keys)))
    (values score fit (nreverse guesses) (nreverse losses))))

(defun notes-score (events &rest keys)
  (values (apply #'run-notes events keys)))

(defun melody-hints (row &key (tempo t) (meter t) (key t) (pickup t))
  "NOTES-TO-SCORE keywords giving ROW's notated tempo, meter, key and pickup."
  (append (and tempo (list :tempo (mt:make-tempo :bpm (melody-bpm row) :beat-unit (melody-unit row))))
          (and meter (list :meter (melody-meter row)))
          (and key (list :key (melody-key row)))
          (and pickup (list :pickup (melody-pickup row)))))

(defun the-voice (score) (first (score-voices score)))

(defun truth-sounding (row &key (semitones 0))
  "((start end midi) ...) of ROW's notation."
  (mapcar (lambda (n) (list (first n) (second n) (+ semitones (third n)))) (melody-notes row)))

(defun first-measure-of (score) (fset:first (sp:score-measure-map score)))

(defun tempo-mark-of (score)
  (first (sp:measure-info-tempo (first-measure-of score))))

(defun note-events (score)
  "The note events of SCORE's voice, in order."
  (remove-if-not (lambda (e) (typep e 'sp:note-event))
                 (mapcar #'second (voice-events score (the-voice score)))))

(defun detected-key (row)
  "MT4's DETECT-KEY of ROW's notation, weighted by duration: MT5's fit of an
in-tune take whose notes all keep the same fraction of their value."
  (car (first (mt:detect-key (mt:pitch-class-histogram
                              (mapcar (lambda (n) (cons (third n) (- (second n) (first n))))
                                      (melody-notes row)))))))

(defun fold-distance (d) (- (mod (+ d 5) 12) 5))

(defun hand-take (notes &key (bpm 100) (hold 1) (start 0))
  "Events for NOTES ((start end midi) whole notes) at BPM quarters per minute."
  (render notes (/ 240 bpm) :hold hold :start start))

(defparameter +in-tune-distances+ '(("silent-night" . -5) ("jingle-bells" . 4))
  "KEY-FIT-HINT-DISTANCE of the in-tune takes with the notated key as the hint,
where it is not 0 (music-theory MT5): Silent Night ranks D minor, F major, then
Bb major (F major leads major, -5); Jingle Bells ranks B minor, B major, then G
major (4). The other eight lead their mode with the notated key.")

(defun in-tune-distance (name)
  (or (cdr (assoc name +in-tune-distances+ :test #'string=)) 0))

(defun key-guesses (score distance)
  "The first measure's guess for a key hint at DISTANCE: none at 0."
  (and (/= 0 distance) (list (list (sp:element-id (first-measure-of score)) "key" 1/2))))

(defparameter +hand-hints+
  (list :tempo (mt:make-tempo :bpm 100) :meter (mt:parse-meter "4/4") :key (mt:parse-key "C")
        :pickup 0))

;;; Round trips of exact takes ------------------------------------------------------------

(deftest-parametrize notes-round-trip-exact
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  ;; In tune, on time, every hint: the notation comes back, and nothing is a
  ;; guess but the key of the two melodies that don't lead their own mode.
  (declare (ignore file title padding end truth expected wrong flagged unflagged))
  (let ((row (melody-row name)) (distance (in-tune-distance name)))
    (multiple-value-bind (score fit guesses losses)
        (apply #'run-notes (render-row row) (melody-hints row))
      (let ((voice (the-voice score)))
        (ok (equal (truth-sounding row) (voice-sounding score voice)) name)
        (ok (equal (mapcar #'fourth (melody-notes row)) (mapcar #'third (voice-starts score voice)))
            "spelled as written")
        (ok (equal (list meter key) (list (mt:meter-string (sp:bar-time score 1))
                                          (mt:key-name (sp:bar-key score 1)))))
        (ok (eq (plusp (melody-pickup row)) (sp:measure-info-pickup-p (first-measure-of score)))
            "the pickup is measure 0")
        (ok (equalp (mt:make-tempo :bpm bpm :beat-unit (melody-unit row))
                    (sp:tempo-mark-tempo (tempo-mark-of score)))
            "the tempo mark is the hint")
        (ok (equal (key-guesses score distance) guesses) "no other guess")
        (ok (equal (mapcar #'first guesses) (mapcar #'sp:element-id (sp:uncertain-elements score))))
        (ok (null losses))
        (ok (null (sp:check-score score)))
        (ok (= 1 (fset:size (sp:score-parts score))))
        (ok (= 1 (notes-fit-rounds fit)))
        (ok (null (notes-fit-ranking fit)))
        (ok (eql 3/2 (notes-fit-origin fit)))
        (ok (eql (melody-whole row) (notes-fit-whole fit)))
        (ok (eql 0 (mt:key-fit-offset (notes-fit-key-fit fit))))
        (ok (every (lambda (n) (eql 0 (third n))) (notes-fit-notes fit)) "every deviation 0")
        (ok (eql distance (mt:key-fit-hint-distance (notes-fit-key-fit fit))))))))

(deftest-parametrize notes-tuning-offset
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  ;; A take 23 cents sharp is the in-tune take: offset 23, every deviation 0,
  ;; the same score. 23 cents flat of the next semitone up too.
  (declare (ignore file title meter key bpm padding end truth expected wrong flagged unflagged))
  (let* ((row (melody-row name))
         (plain (apply #'notes-score (render-row row) (melody-hints row))))
    (multiple-value-bind (score fit) (apply #'run-notes (render-row row :cents 23) (melody-hints row))
      (ok (sp:score-equal plain score) name)
      (ok (eql 23 (mt:key-fit-offset (notes-fit-key-fit fit))))
      (ok (every (lambda (n) (eql 0 (third n))) (notes-fit-notes fit))))
    (multiple-value-bind (score fit) (apply #'run-notes (render-row row :cents 77 :semitones -1)
                                            (melody-hints row))
      (ok (sp:score-equal plain score) "77 cents above a semitone down")
      (ok (eql -23 (mt:key-fit-offset (notes-fit-key-fit fit)))))))

(deftest-parametrize notes-without-a-tempo
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  ;; An exact take with no :TEMPO: the estimate is the notated tempo, so the
  ;; score is the hinted one but for the tempo mark's confidence, which is
  ;; the one more guess.
  (declare (ignore file title meter key padding end truth expected wrong flagged unflagged))
  (let* ((row (melody-row name))
         (events (render-row row))
         (hinted (apply #'notes-score events (melody-hints row))))
    (multiple-value-bind (score fit guesses) (apply #'run-notes events (melody-hints row :tempo nil))
      (let ((mark (tempo-mark-of score)))
        (ok (equal (voice-sounding hinted (the-voice hinted)) (voice-sounding score (the-voice score)))
            name)
        (ok (equal (mapcar #'third (voice-starts hinted (the-voice hinted)))
                   (mapcar #'third (voice-starts score (the-voice score)))))
        (ok (eql bpm (mt:tempo-bpm (sp:tempo-mark-tempo mark))) "the notated tempo")
        (ok (eql (melody-unit row) (mt:tempo-beat-unit (sp:tempo-mark-tempo mark))))
        (ok (eql 1/2 (sp:element-confidence mark)))
        (ok (equal (append (key-guesses score (in-tune-distance name))
                           (list (list (sp:element-id mark) "tempo" 1/2)))
                   guesses))
        (ok (equal (nth-value 1 (estimate-tempo (onsets-of events) :beat-unit (melody-unit row)))
                   (notes-fit-ranking fit))
            "the ranking is ESTIMATE-TEMPO's")
        (ok (<= 1 (notes-fit-rounds fit) +alignment-rounds+))
        (ok (eql (/ 60 (* bpm (melody-unit row))) (notes-fit-whole fit)))
        (ok (null (sp:check-score score)))))))

;;; Takes with errors ---------------------------------------------------------------------

(defun take-stats (row score)
  "(right flagged wrong-unflagged total) of SCORE's starts against ROW's notation."
  (let ((right 0) (flagged 0) (wrong-unflagged 0)
        (starts (voice-starts score (the-voice score))))
    (loop for s in starts
          for n in (melody-notes row)
          for uncertain = (< (sp:element-confidence (fifth s)) 0.8)
          do (when (= (first s) (first n)) (incf right))
             (when uncertain (incf flagged))
             (when (and (/= (first s) (first n)) (not uncertain)) (incf wrong-unflagged)))
    (list right flagged wrong-unflagged (length starts))))

(deftest-parametrize notes-sung-takes
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  ;; Sung 23 cents sharp, each note detuned by up to 15 cents and placed up to
  ;; 30 ms off, every hint given: every pitch comes back, the fitted offset is
  ;; within 8 cents of 23 (the reference finds 15 to 31), a pitch is a guess
  ;; exactly when it lies more than 22.36 cents off the fitted tuning, and every
  ;; onset off the notation is flagged.
  (declare (ignore file title meter key bpm padding end truth expected wrong flagged unflagged))
  (let ((row (melody-row name)))
    (dolist (k '(1 2 3))
      (multiple-value-bind (score fit guesses)
          (apply #'run-notes (render-row row :k k :jitter 30 :cents 23 :detune 15) (melody-hints row))
        (let ((starts (voice-starts score (the-voice score)))
              (offset (mt:key-fit-offset (notes-fit-key-fit fit))))
          (ok (equal (mapcar #'third (melody-notes row)) (mapcar #'second starts))
              (format nil "~A take ~D: every MIDI number" name k))
          (ok (<= 15 offset 31) (format nil "offset ~D" offset))
          (ok (loop for (id nil deviation) in (notes-fit-notes fit)
                    for pc = (- 1 (expt (/ deviation 50) 2))
                    for guess = (find id guesses :key #'first :test #'equal)
                    always (if (< pc 0.8)
                               (and guess (<= (third guess) pc))
                               (not (equal "pitch" (second guess)))))
              "pitch guesses as the deviations give them")
          (ok (zerop (third (take-stats row score))) "every misplaced onset is flagged")
          (ok (null (sp:check-score score))))))))

(deftest notes-sung-takes-overall
  ;; The 30 takes above without the :TEMPO hint (meter, key and pickup given):
  ;; the alignment finds every tempo within 0.2%, puts 760 of the 762 onsets
  ;; where the notation has them, and leaves none misplaced unflagged. It flags
  ;; 10 notes for their onsets (the exact Python mirror of the timing rules
  ;; agrees) and 5 for their pitch.
  (let ((right 0) (flagged 0) (wrong-unflagged 0) (total 0) (worst 0) (whats '()))
    (dolist (row +performance-rows+)
      (dolist (k '(1 2 3))
        (multiple-value-bind (score fit guesses)
            (apply #'run-notes (render-row row :k k :jitter 30 :cents 23 :detune 15)
                   (melody-hints row :tempo nil))
          (declare (ignore fit))
          (let ((stats (take-stats row score))
                (bpm (mt:tempo-bpm (sp:tempo-mark-tempo (tempo-mark-of score)))))
            (setf worst (max worst (tempo-error bpm (melody-bpm row))))
            (dolist (g guesses) (push (second g) whats))
            (incf right (first stats)) (incf flagged (second stats))
            (incf wrong-unflagged (third stats)) (incf total (fourth stats))))))
    (ok (= 762 total))
    (ok (<= worst 1/500) (format nil "worst tempo error ~,4F" worst))
    (ok (= 760 right) (format nil "~D of ~D onsets as notated" right total))
    (ok (zerop wrong-unflagged))
    (ok (= 10 (count "quantization" whats :test #'string=))
        (format nil "~D for their onsets" (count "quantization" whats :test #'string=)))
    (ok (= 5 (count "pitch" whats :test #'string=))
        (format nil "~D for their pitch" (count "pitch" whats :test #'string=)))
    (ok (= 30 (count "tempo" whats :test #'string=)) "every tempo mark")
    (ok (= flagged 15) (format nil "~D notes flagged" flagged))))

;;; Hints and guesses ---------------------------------------------------------------------

(deftest notes-meter-and-downbeat-guesses
  (let* ((row (melody-row "twinkle")) (events (render-row row)))
    (multiple-value-bind (score fit guesses) (apply #'run-notes events (melody-hints row :meter nil :pickup nil))
      (declare (ignore fit))
      (let ((m1 (first-measure-of score)))
        (ok (equal "4/4" (mt:meter-string (sp:measure-info-time m1))) "4/4 assumed")
        (ok (eql 1/2 (sp:element-confidence m1)))
        (ok (equal (list (list (sp:element-id m1) "meter" 1/2)) guesses)
            "meter and downbeat tie: meter first")))
    (multiple-value-bind (score fit guesses) (apply #'run-notes events (melody-hints row :pickup nil))
      (declare (ignore fit))
      (ok (equal (list (list (sp:element-id (first-measure-of score)) "downbeat" 1/2)) guesses)
          "no pickup hint: the downbeat is a guess"))
    (ok (null (nth-value 2 (apply #'run-notes events (melody-hints row)))) ":PICKUP 0 is no guess"))
  ;; A 3/4 melody read in the default 4/4: other barlines, the same notes.
  (let ((row (melody-row "minuet-in-g")))
    (let ((score (apply #'notes-score (render-row row) (melody-hints row :meter nil))))
      (ok (equal "4/4" (mt:meter-string (sp:bar-time score 1))))
      (ok (equal (truth-sounding row) (voice-sounding score (the-voice score))))
      (ok (null (sp:check-score score))))))

(deftest-parametrize notes-detected-key
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  ;; No :KEY: the key is the fit's, MT4's DETECT-KEY of the notation in tune;
  ;; its confidence is the fit's correlation.
  (declare (ignore file title meter key bpm padding end truth expected wrong flagged unflagged))
  (let ((row (melody-row name)))
    (multiple-value-bind (score fit guesses) (apply #'run-notes (render-row row) (melody-hints row :key nil))
      (let* ((m1 (first-measure-of score))
             (kf (notes-fit-key-fit fit))
             (r (max 0d0 (min 1d0 (mt:key-fit-correlation kf)))))
        (ok (equalp (detected-key row) (sp:measure-info-key m1)) name)
        (ok (equalp (mt:key-fit-key kf) (sp:measure-info-key m1)))
        (ok (eql r (sp:element-confidence m1)) "the correlation")
        (ok (null (mt:key-fit-hint kf)))
        (ok (equal (and (< r 0.8) (list (list (sp:element-id m1) "key" r))) guesses))))))

(deftest-parametrize notes-key-hint-distance
    ((file name title meter key bpm padding end truth expected wrong flagged unflagged)
     :rows +performance-rows+)
  ;; Sung a semitone below the notated key, with that key as the hint: the hint
  ;; distance moves down by one (folded into -5 .. 6): -1 for the eight
  ;; melodies at 0 in tune. The key stays the hint, the notes stay as sung,
  ;; and the nonzero distance flags the first measure "key".
  (declare (ignore file title meter key bpm padding end truth expected wrong flagged unflagged))
  (let* ((row (melody-row name))
         (in-tune (mt:key-fit-hint-distance
                   (notes-fit-key-fit (nth-value 1 (apply #'run-notes (render-row row) (melody-hints row)))))))
    (multiple-value-bind (score fit guesses) (apply #'run-notes (render-row row :semitones -1) (melody-hints row))
      (let ((distance (mt:key-fit-hint-distance (notes-fit-key-fit fit)))
            (m1 (first-measure-of score)))
        (ok (eql (in-tune-distance name) in-tune) name)
        (ok (eql (fold-distance (1- in-tune)) distance) "a semitone below")
        (ok (or (/= 0 in-tune) (eql -1 distance)))
        (ok (equalp (melody-key row) (sp:measure-info-key m1)) "the hint stays the key")
        (ok (equal (truth-sounding row :semitones -1) (voice-sounding score (the-voice score)))
            "the notes as sung")
        (ok (eql 1/2 (sp:element-confidence m1)))
        (ok (equal (list (sp:element-id m1) "key" 1/2) (assoc (sp:element-id m1) guesses :test #'equal)))))))

(deftest notes-uncertainty-report
  ;; No hint at all, Twinkle in tune and on time: 4/4, C major and the tempo
  ;; are guessed. The report is the first measure (meter, the least: meter and
  ;; downbeat 1/2 tie, meter first) and the tempo mark, in document order.
  (multiple-value-bind (score fit guesses) (run-notes (render-row (melody-row "twinkle")))
    (let ((m1 (first-measure-of score)) (mark (tempo-mark-of score)))
      (ok (equal "C major" (mt:key-name (sp:measure-info-key m1))))
      (ok (> (mt:key-fit-correlation (notes-fit-key-fit fit)) 0.8))
      (ok (equal (list (list (sp:element-id m1) "meter" 1/2) (list (sp:element-id mark) "tempo" 1/2))
                 guesses))
      (ok (equal (mapcar #'first guesses) (mapcar #'sp:element-id (sp:uncertain-elements score)))))))

(deftest notes-input-confidence
  ;; Two notes the source doubts (1/2) are flagged "input"; 9/10 is no guess.
  (let* ((row (melody-row "ode-to-joy"))
         (events (loop for e in (render-row row)
                       for i from 0
                       collect (case i
                                 ((2 5) (append e (list :confidence 1/2)))
                                 (7 (append e (list :confidence 9/10)))
                                 (t e)))))
    (multiple-value-bind (score fit guesses) (apply #'run-notes events (melody-hints row))
      (let ((notes (note-events score)) (ids (mapcar #'first (notes-fit-notes fit))))
        (ok (equal (list (list (nth 2 ids) "input" 1/2) (list (nth 5 ids) "input" 1/2)) guesses))
        (ok (equal (list (nth 2 ids) (nth 5 ids)) (mapcar #'sp:element-id (sp:uncertain-elements score))))
        (ok (eql 9/10 (sp:element-confidence (find (nth 7 ids) notes :key #'sp:element-id :test #'equal))))))))

(deftest notes-pitch-confidence
  ;; One note sung 40 cents sharp in a take otherwise in tune: the offset stays
  ;; near 0 and that note is flagged "pitch" with 1 - (deviation / 50)^2.
  (let* ((row (melody-row "old-hundredth"))
         (events (loop for e in (render-row row)
                       for i from 0
                       collect (if (= i 4) (list :onset (getf e :onset) :offset (getf e :offset)
                                                 :pitch (+ (getf e :pitch) 2/5))
                                   e))))
    (multiple-value-bind (score fit guesses) (apply #'run-notes events (melody-hints row))
      (declare (ignore score))
      (destructuring-bind (id midi deviation) (nth 4 (notes-fit-notes fit))
        (ok (eql (fourth (nth 4 (ninth row))) midi))
        (ok (<= 35 deviation 45) (format nil "deviation ~A" deviation))
        (ok (equal (list (list id "pitch" (- 1 (expt (/ deviation 50) 2)))) guesses))))))

;;; Rests, legato, overlaps, monophony -----------------------------------------------------

(deftest notes-rests
  ;; At quarter = 100, every hint, each note held its full value: an eighth
  ;; rest (not shorter than +LEGATO-GAP+) and a quarter rest stay, and so does
  ;; the half rest that ends the take. A note's end lands on the grid its beat
  ;; chose from its onsets (import.lisp): the eighth rest on beat 2 is there
  ;; because D4 divides that beat.
  (let* ((notes '((0 1/4 60) (3/8 1/2 62) (1/2 3/4 64) (1 3/2 72)))
         (score (apply #'notes-score (hand-take notes) +hand-hints+))
         (events (mapcar #'second (voice-events score (the-voice score)))))
    (ok (equal notes (voice-sounding score (the-voice score))))
    (ok (equal '(sp:note-event sp:rest-event sp:note-event sp:note-event sp:rest-event
                 sp:note-event sp:rest-event)
               (mapcar #'type-of events)))
    (ok (equal '(1/4 1/8 1/8 1/4 1/4 1/2 1/2) (mapcar #'sp:event-duration events)))
    (ok (null (sp:check-score score)))))

(deftest notes-legato
  ;; C4 D4 E4 as an eighth and two sixteenths, then F4 a quarter, each held
  ;; half its value. The first beat's grid is sixteenths, so C4 ends a
  ;; sixteenth early; that gap is shorter than an eighth and is absorbed. D4
  ;; and E4 end halfway between two grid points and take the later one. F4's
  ;; beat is undivided: its end, halfway, takes the beat's end, and the take
  ;; ends with a half rest.
  (let* ((notes '((0 1/8 60) (1/8 3/16 62) (3/16 1/4 64) (1/4 1/2 65)))
         (score (apply #'notes-score (hand-take notes :hold 1/2) +hand-hints+)))
    (ok (equal notes (voice-sounding score (the-voice score))))
    (ok (equal '(1/8 1/16 1/16 1/4 1/2)
               (mapcar #'sp:event-duration (mapcar #'second (voice-events score (the-voice score))))))))

(deftest notes-overlaps-and-order
  ;; Each note held 80 ms into the next: cut where the next one starts, the
  ;; same score. The events in reverse order, or as a vector: the same score.
  (let* ((row (melody-row "frere-jacques"))
         (events (render-row row))
         (plain (apply #'notes-score events (melody-hints row)))
         (overlapping (loop for (e next) on events
                            collect (if next
                                        (list :onset (getf e :onset) :offset (+ (getf next :onset) 2/25)
                                              :pitch (getf e :pitch))
                                        e))))
    (ok (equal (voice-sounding plain (the-voice plain))
               (voice-sounding (apply #'notes-score overlapping (melody-hints row))
                               (the-voice (apply #'notes-score overlapping (melody-hints row))))))
    (ok (sp:score-equal plain (apply #'notes-score (reverse events) (melody-hints row))))
    (ok (sp:score-equal plain (apply #'notes-score (coerce events 'vector) (melody-hints row))))
    (ok (sp:score-equal plain (apply #'notes-score events (melody-hints row))) "deterministic")))

(deftest notes-monophony
  ;; A 40 ms glitch 20 ms before the fifth note snaps to that note's place: the
  ;; held note wins, the glitch is dropped and reported once, and the score is
  ;; the clean take's.
  (let* ((row (melody-row "twinkle"))
         (events (render-row row))
         (fifth-onset (getf (nth 4 events) :onset))
         (glitch (list :onset (- fifth-onset 1/50) :offset (+ fifth-onset 1/50) :pitch 75))
         (with-glitch (append (subseq events 0 4) (list glitch) (subseq events 4))))
    (multiple-value-bind (score fit guesses losses) (apply #'run-notes with-glitch (melody-hints row))
      (declare (ignore guesses))
      (let ((clean (apply #'notes-score events (melody-hints row))))
        (ok (equal (voice-sounding clean (the-voice clean)) (voice-sounding score (the-voice score))))
        (ok (equal '(("notes" :notes :from)) losses))
        (ok (= (length with-glitch) (length (notes-fit-notes fit))))
        (destructuring-bind (id midi deviation) (nth 4 (notes-fit-notes fit))
          (ok (null id) "the glitch has no note")
          (ok (eql 75 midi))
          (ok (eql 0 deviation)))
        (ok (stringp (first (nth 5 (notes-fit-notes fit)))))))))

;;; Provenance and FIT ----------------------------------------------------------------------

(deftest notes-provenance
  (let* ((row (melody-row "amazing-grace"))
         (events (render-row row :jitter 30)))
    (multiple-value-bind (score fit) (apply #'run-notes events (melody-hints row))
      (let ((elements (sp:score-elements score)))
        (ok (minted-ids-p score) "ids minted in document order")
        (ok (every (lambda (e)
                     (let ((p (sp:element-provenance e)))
                       (and p (eq :transcription (sp:provenance-source p))
                            (equal "score-backend-midi" (sp:provenance-backend p)))))
                   elements))
        ;; Notes: their event's seconds; ties carry them on.
        (ok (loop for (id) in (notes-fit-notes fit)
                  for e in events
                  always (equal (list (getf e :onset) (getf e :offset))
                                (sp:provenance-time-range
                                 (sp:element-provenance (sp:find-element score id))))))
        (ok (every (lambda (e) (sp:provenance-time-range (sp:element-provenance e))) (note-events score))
            "every piece has its note's seconds")
        ;; Measures: contiguous seconds from the origin.
        (let ((ranges (mapcar (lambda (m) (sp:provenance-time-range (sp:element-provenance m)))
                              (seq-list (sp:score-measure-map score)))))
          (ok (eql (notes-fit-origin fit) (first (first ranges))))
          (ok (loop for (a b) on ranges while b always (eql (second a) (first b))))
          (ok (eql (+ (notes-fit-origin fit) (* (notes-fit-whole fit) (sp:score-duration score)))
                   (second (car (last ranges))))))
        (ok (null (sp:provenance-time-range (sp:element-provenance (fset:first (sp:score-parts score)))))
            "the part has none")
        (ok (< (abs (- (getf (first events) :onset) (notes-fit-origin fit))) 1/20)
            "the fitted origin, near the first onset")))
    (ok (every (lambda (e) (eq :midi (sp:provenance-source (sp:element-provenance e))))
               (sp:score-elements (apply #'notes-score events :source :midi (melody-hints row))))
        ":SOURCE")))

;;; Conditions ------------------------------------------------------------------------------

(defparameter +good-event+ '(:onset 0 :offset 3/5 :pitch 60))

(deftest-parametrize notes-bad-events
    ((label bad)
     ("no onset" '(:offset 1 :pitch 60))
     ("onset at the offset" '(:onset 1 :offset 1 :pitch 60))
     ("onset after the offset" '(:onset 2 :offset 1 :pitch 60))
     ("pitch above 127" '(:onset 1 :offset 2 :pitch 128))
     ("negative pitch" '(:onset 1 :offset 2 :pitch -1))
     ("pitch a name" '(:onset 1 :offset 2 :pitch "C4"))
     ("confidence above 1" '(:onset 1 :offset 2 :pitch 60 :confidence 3/2))
     ("negative confidence" '(:onset 1 :offset 2 :pitch 60 :confidence -1/10))
     ("odd plist" '(:onset 1 :offset 2 :pitch))
     ("dotted plist" '(:onset 1 :offset 2 :pitch . 60))
     ("not a list" 60))
  (let ((c (signalled (lambda () (notes-to-score (list +good-event+ bad '(:onset 1 :offset 2 :pitch 62)))))))
    (ok (typep c 'sp:score-format-error) label)
    (ok (and (typep c 'sp:score-format-error)
             (equal (list :notes "bad event" 1)
                    (list (sp:score-format-error-format c) (sp:score-error-reason c)
                          (sp:score-format-error-position c)))))))

(deftest notes-bad-event-restarts
  (let ((good (list +good-event+ '(:onset 3/5 :offset 6/5 :pitch 62)))
        (bad '(:onset 1 :offset 1/2 :pitch 64)))
    ;; CONTINUE drops it: the score of the good events; its FIT entry is NIL.
    (multiple-value-bind (score fit)
        (handler-bind ((sp:score-format-error (lambda (c) (continue c))))
          (run-notes (append good (list bad))))
      (ok (sp:score-equal (notes-score good) score) "CONTINUE drops it")
      (ok (= 3 (length (notes-fit-notes fit))))
      (ok (null (third (notes-fit-notes fit)))))
    ;; USE-VALUE replaces it, and the replacement is checked again.
    (let ((seen 0))
      (let ((score (handler-bind ((sp:score-format-error
                                    (lambda (c)
                                      (incf seen)
                                      (use-value (if (= seen 1) '(:pitch 64) '(:onset 6/5 :offset 9/5 :pitch 64))
                                                 c))))
                     (notes-score (append good (list bad))))))
        (ok (= 2 seen) "a bad replacement signals again")
        (ok (sp:score-equal (notes-score (append good (list '(:onset 6/5 :offset 9/5 :pitch 64)))) score))))))

(deftest notes-no-events
  (let ((c (signalled (lambda () (notes-to-score '())))))
    (ok (typep c 'sp:score-format-error))
    (ok (and (typep c 'sp:score-format-error)
             (equal (list :notes "no events" nil)
                    (list (sp:score-format-error-format c) (sp:score-error-reason c)
                          (sp:score-format-error-position c))))))
  (let ((score (handler-bind ((sp:score-format-error (lambda (c) (use-value (list +good-event+) c))))
                 (notes-score #()))))
    (ok (sp:score-equal (notes-score (list +good-event+)) score) "USE-VALUE: other events"))
  ;; Every event dropped: no events.
  (let ((reasons '()))
    (handler-case
        (handler-bind ((sp:score-format-error
                         (lambda (c)
                           (push (sp:score-error-reason c) reasons)
                           (when (equal "bad event" (sp:score-error-reason c)) (continue c)))))
          (notes-to-score '((:onset 1) (:onset 2))))
      (sp:score-format-error () nil))
    (ok (equal '("bad event" "bad event" "no events") (reverse reasons)))))

(deftest notes-impossible-pickup
  (let ((events (list +good-event+ '(:onset 3/5 :offset 6/5 :pitch 62))))
    (ok (signals-type (lambda () (notes-to-score events :pickup 1)) 'type-error) "a bar is no pickup")
    (ok (signals-type (lambda () (notes-to-score events :pickup 3/4 :meter (mt:parse-meter "3/4")))
                      'type-error))
    (let ((score (handler-bind ((type-error (lambda (c) (store-value 1/4 c))))
                   (notes-score events :pickup 5/4 :tempo (mt:make-tempo :bpm 100)))))
      (ok (sp:measure-info-pickup-p (first-measure-of score)) "STORE-VALUE: a quarter pickup")
      (ok (eql 1/4 (sp:measure-info-length (first-measure-of score)))))))

(deftest-parametrize notes-argument-errors
    ((label thunk)
     ("events not a sequence" (lambda () (notes-to-score 42)))
     ("key" (lambda () (notes-to-score (list +good-event+) :key "C")))
     ("meter" (lambda () (notes-to-score (list +good-event+) :meter "4/4")))
     ("tempo" (lambda () (notes-to-score (list +good-event+) :tempo 120)))
     ("negative pickup" (lambda () (notes-to-score (list +good-event+) :pickup -1/4)))
     ("float pickup" (lambda () (notes-to-score (list +good-event+) :pickup 0.25)))
     ("subdivision 5" (lambda () (notes-to-score (list +good-event+) :subdivisions '(1 5))))
     ("source" (lambda () (notes-to-score (list +good-event+) :source "mic")))
     ("backend" (lambda () (notes-to-score (list +good-event+) :backend :cdcl))))
  (ok (signals-type thunk 'type-error) label))

(deftest notes-go-through-sat
  (let ((given (make-instance 'counting-backend))
        (default (make-instance 'counting-backend))
        (events (render-row (melody-row "twinkle"))))
    (let ((sat:*sat-backend* default))
      (notes-score events :backend given)
      (ok (and (plusp (backend-calls given)) (zerop (backend-calls default)))
          "the backend given is used, and the default is not")
      (notes-score events)
      (ok (plusp (backend-calls default)) "*SAT-BACKEND* otherwise"))
    (let ((sat:*sat-backend* nil))
      (ok (signals-type (lambda () (notes-to-score events)) 'sat:sat-no-backend)))))

(deftest notes-no-key-evidence
  ;; The twelve chromatic notes as equal quarters, in tune: every fold of the
  ;; fit is constant. NOTES-TO-SCORE answers NO-KEY-EVIDENCE itself: no fit, C
  ;; major with confidence 0, the MIDI numbers rounded.
  (let ((events (hand-take (loop for k below 12 collect (list (/ k 4) (/ (1+ k) 4) (+ 60 k)))))
        (hints (list :tempo (mt:make-tempo :bpm 100) :meter (mt:parse-meter "4/4") :pickup 0)))
    (multiple-value-bind (score fit guesses) (apply #'run-notes events hints)
      (let ((m1 (first-measure-of score)))
        (ok (null (notes-fit-key-fit fit)))
        (ok (equal "C major" (mt:key-name (sp:measure-info-key m1))))
        (ok (eql 0 (sp:element-confidence m1)))
        (ok (equal (list (sp:element-id m1) "key" 0) (first guesses)))
        (ok (equal (loop for k below 12 collect (+ 60 k)) (mapcar #'second (notes-fit-notes fit))))
        (ok (equal (loop for k below 12 collect (list (/ k 4) (/ (1+ k) 4) (+ 60 k)))
                   (voice-sounding score (the-voice score))))))
    (ok (null (notes-fit-key-fit (nth-value 1 (apply #'run-notes events :key (mt:parse-key "C") hints))))
        "with a hint: no fit, and no key guess")))

(deftest notes-ambiguous-spelling-reaches-the-caller
  ;; One G#4 in C major: MT4's rules tie (S7), as in SMF-TO-SCORE.
  (let* ((seen '())
         (score (handler-bind ((mt:ambiguous-spelling
                                 (lambda (c)
                                   (push (mt:ambiguous-spelling-midi c) seen)
                                   (use-value (mt:parse-pitch "Ab4") c))))
                  (apply #'notes-score (hand-take '((0 1 68))) +hand-hints+))))
    (ok (equal '(68) seen))
    (ok (equal '("Ab4") (mapcar #'third (voice-starts score (the-voice score)))))))
