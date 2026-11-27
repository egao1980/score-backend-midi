;;;; SC4 import, part 2: the measure map, from meta events and hints. Rules for
;;;; SMF-TO-SCORE (import.lisp); no functions of their own.
;;;;
;;;; Time. With DIVISION ticks per quarter note, tick t is the position
;;;; t / (4 * DIVISION) whole notes. An SMPTE division signals
;;;; SCORE-FORMAT-ERROR (FORMAT :MIDI, REASON "SMPTE division") inside a
;;;; USE-VALUE restart whose value, an integer 1..32767, is used as DIVISION.
;;;; Meta events are read from every track, merged as MIDI-PROTOCOL:MERGE-TRACKS
;;;; orders them; of several of one kind at one tick, the last counts. The
;;;; content ends at C, the position of the latest tick of any track (its
;;;; END-OF-TRACK-EVENT), which is at least the end of every note.
;;;;
;;;; Bars. A time signature n/d (a TIME-SIGNATURE-EVENT's NUMERATOR and
;;;; DENOMINATOR) has the meter (make-meter :numerators (list n) :denominator d)
;;;; and bars n/d long. The signature in force at tick 0 is the :METER hint
;;;; when given, else the event at tick 0, else 4/4. Bars are laid from 0, each
;;;; as long as its signature's bar, except that where a time signature event
;;;; falls inside a bar, that bar ends there and the new signature starts a bar
;;;; at its tick. Laying stops at the first bar that ends at or after C (at
;;;; least one bar when C > 0; none when C = 0), so the last bar is never cut:
;;;; the score ends at E, the end of the last bar. A run is the bars laid from
;;;; one signature.
;;;;
;;;; Meters and lengths, for bars B0 .. Bm-1 (m >= 1):
;;;;   meter(Bi) is its signature's meter, except:
;;;;     pickup  when m >= 2, B0 is the only bar of its run, and B0 is shorter
;;;;             than B1's signature bar: meter(B0) = meter(B1), and measure 0
;;;;             is a pickup (PICKUP-P T);
;;;;     final   when m >= 2, Bm-1 is the only bar of its run and shorter than
;;;;             Bm-2's signature bar: meter(Bm-1) = Bm-2's signature's meter.
;;;;   Measure i has TIME meter(Bi) when i = 0 or meter(Bi) isn't EQUALP to
;;;;   meter(Bi-1), else NIL; LENGTH the bar's length when that isn't
;;;;   (meter-measure-duration meter(Bi)), else NIL. So the export's actual-length
;;;;   signatures of a pickup and of a short final bar (export.lisp) come back as
;;;;   a pickup and a short final measure; a short bar elsewhere comes back as a
;;;;   meter change. The last measure's BARLINE is :FINAL. Repeats, endings and
;;;;   jumps never appear: a MIDI file is played as written.
;;;;
;;;; Keys. A KEY-SIGNATURE-EVENT with SHARPS f and MINOR-P is the key whose
;;;; signature is f in that mode: tonic (fifths-pitch-class f) in major,
;;;; (fifths-pitch-class (+ f 3)) in minor. It sets the KEY of the measure whose
;;;; bar holds its tick (start <= tick < end; of several in one bar, the last).
;;;; Measures after the first without an event of their own have no KEY. The
;;;; first measure's KEY:
;;;;   the :KEY hint when given;
;;;;   else the key of a key event in the first bar;
;;;;   else the first key of (detect-key (pitch-class-histogram K :weight
;;;;     :count)), K the keys of every imported note (music-theory MT4); C major
;;;;     when that is NIL.
;;;;
;;;; Tempo. A TEMPO-EVENT of u microseconds per quarter note at tick t becomes a
;;;; TEMPO-MARK of the measure whose bar holds t, OFFSET the position of t minus
;;;; the bar's start, TEMPO (make-tempo :bpm b :beat-unit w): w is the BEAT-UNIT
;;;; of the bar's meter (1/4 when NIL), b = floor(100 * 15000000 / (u * w) + 1/2)
;;;; / 100 (two decimals, exact: 833333 us at w 1/4 is 72). With the :TEMPO
;;;; hint, the tempo mark at offset 0 of the first measure is the hint (in place
;;;; of a tempo event at tick 0, or added when there is none). A measure's tempo
;;;; marks are in OFFSET order; of several at one tick, the last event counts.
;;;;
;;;; Rehearsal marks. A MARKER-EVENT whose text doesn't start with
;;;; +CHORD-TEXT-PREFIX+ becomes the REHEARSAL-MARK of the measure whose bar
;;;; holds its tick; of several in one bar, the first.
;;;;
;;;; Hints and confidence. Imported measures, tempo marks and rehearsal marks
;;;; have confidence NIL, except for these guesses, which set the confidence of
;;;; the first measure (the least of those that apply) or of the tempo mark:
;;;;   meter  no :METER hint and no time signature event at tick 0 (4/4 was
;;;;          assumed), or a :METER hint whose numerators' sum or denominator
;;;;          differs from the event at tick 0: +GUESS-CONFIDENCE+.
;;;;   key    a :KEY hint that differs from the first bar's key event (another
;;;;          KEY-SIGNATURE or mode), or, with no such event, whose tonic pitch
;;;;          class or mode differs from the detected key: +GUESS-CONFIDENCE+.
;;;;          No hint and no event: the detected key's correlation clamped to
;;;;          0..1, or 0 when the key fell back to C major.
;;;;   tempo  a :TEMPO hint whose microseconds per quarter,
;;;;          floor(15000000 / (bpm * beat-unit) + 1/2), differ from the tempo
;;;;          event at tick 0: +GUESS-CONFIDENCE+ on that tempo mark.
;;;; A hint never overrides the file silently: it wins, and the disagreement is
;;;; recorded (brief: Hints).

(in-package #:score-backend-midi)

;;; Time --------------------------------------------------------------------------

(defun %division (smf)
  "SMF's ticks per quarter note. An SMPTE division signals SCORE-FORMAT-ERROR
(REASON \"SMPTE division\") inside a USE-VALUE restart whose value is used."
  (let ((division (midi-protocol:smf-division smf)))
    (loop while (midi-protocol:smpte-division-p division)
          do (restart-case (error 'score-protocol:score-format-error
                                  :format :midi :reason "SMPTE division")
               (use-value (ticks)
                 :report "Use these ticks per quarter note (an integer 1..32767)."
                 :interactive (lambda ()
                                (format *query-io* "~&Ticks per quarter note: ")
                                (finish-output *query-io*)
                                (list (read *query-io*)))
                 (check-type ticks (integer 1 32767))
                 (setf division ticks))))
    division))

(defun %merged-timed (smf)
  "Every event of SMF as (TICK . EVENT), merged as MERGE-TRACKS orders them."
  (midi-protocol:track-to-absolute (midi-protocol:merge-tracks (midi-protocol:smf-tracks smf))))

(defun %content-end (smf)
  "C in ticks: the latest tick of any track."
  (reduce #'max (midi-protocol:smf-tracks smf)
          :key (lambda (track) (reduce #'+ track :key #'midi-protocol:midi-event-delta))
          :initial-value 0))

(defun %last-per-tick (timed predicate)
  "((TICK . EVENT) ...) of the TIMED events satisfying PREDICATE, ascending by
tick, the last of several at one tick."
  (let ((out '()))
    (loop for (tick . event) in timed
          when (funcall predicate event)
            do (if (and out (= tick (car (first out))))
                   (setf (cdr (first out)) event)
                   (push (cons tick event) out)))
    (nreverse out)))

(defun %starts-with-p (prefix text)
  (and (>= (length text) (length prefix))
       (string= prefix text :end2 (length prefix))))

;;; Bars ----------------------------------------------------------------------------

(defstruct (%bar (:constructor %make-bar (start length signature run))
                 (:copier nil) (:predicate nil))
  "A laid bar (Bars): START and LENGTH in whole notes, the SIGNATURE meter it was
laid from and its RUN; then the measure's METER, TIME and LENGTH-SLOT, KEY,
PICKUP-P, TEMPO marks (%MARKs), REHEARSAL text, CONFIDENCE and the WHAT of
that confidence, and its TIME-RANGE (NIL for an SMF; NOTES-TO-SCORE sets the
bar's seconds, notes.lisp)."
  start length signature run meter time length-slot key pickup-p tempo rehearsal
  confidence what time-range)

(defstruct (%mark (:constructor %make-mark (offset tempo confidence))
                  (:copier nil) (:predicate nil))
  "A tempo mark of a bar: OFFSET, a music-theory TEMPO, CONFIDENCE."
  offset tempo confidence)

(defun %bar-end (bar) (+ (%bar-start bar) (%bar-length bar)))

(defun %bar-at (bars x)
  "The bar of BARS that holds the position X (START <= X < END), or NIL."
  (find-if (lambda (bar) (and (<= (%bar-start bar) x) (< x (%bar-end bar)))) bars))

(defun %event-meter (event)
  (music-theory:make-meter :numerators (list (midi-protocol:time-signature-event-numerator event))
                           :denominator (midi-protocol:time-signature-event-denominator event)))

(defun %lay-bars (c points)
  "The bars laid from 0 up to the first that ends at or after C. POINTS is
((position . meter) ...) ascending, the first at 0: each starts a run."
  (let ((bars '()) (position 0) (run -1) (meter nil))
    (loop while (< position c)
          do (loop while (and points (<= (car (first points)) position))
                   do (setf meter (cdr (pop points)))
                      (incf run))
             (let ((stop (+ position (music-theory:meter-measure-duration meter))))
               (when (and points (< (car (first points)) stop))
                 (setf stop (car (first points))))
               (push (%make-bar position (- stop position) meter run) bars)
               (setf position stop)))
    (nreverse bars)))

(defun %set-meters (bars)
  "Each bar's METER, TIME, LENGTH-SLOT and PICKUP-P (Meters and lengths)."
  (let ((m (length bars)))
    (flet ((alone-p (bar) (= 1 (count (%bar-run bar) bars :key #'%bar-run)))
           (signature-length (bar) (music-theory:meter-measure-duration (%bar-signature bar))))
      (dolist (bar bars)
        (setf (%bar-meter bar) (%bar-signature bar)))
      (when (>= m 2)
        (let ((b0 (first bars)) (b1 (second bars))
              (last (car (last bars))) (before (nth (- m 2) bars)))
          (when (and (alone-p b0) (< (%bar-length b0) (signature-length b1)))
            (setf (%bar-meter b0) (%bar-signature b1)
                  (%bar-pickup-p b0) t))
          (when (and (alone-p last) (< (%bar-length last) (signature-length before)))
            (setf (%bar-meter last) (%bar-signature before)))))
      (loop for bar in bars
            for previous = nil then meter
            for meter = (%bar-meter bar)
            do (setf (%bar-time bar) (and (or (null previous) (not (equalp meter previous))) meter)
                     (%bar-length-slot bar)
                     (and (/= (%bar-length bar) (music-theory:meter-measure-duration meter))
                          (%bar-length bar)))))))

;;; Keys, tempo, rehearsal, hints ----------------------------------------------------

(defun %event-key (event)
  "The key whose signature is the KEY-SIGNATURE-EVENT's SHARPS in its mode."
  (let ((f (midi-protocol:key-signature-event-sharps event)))
    (if (midi-protocol:key-signature-event-minor-p event)
        (music-theory:make-key :tonic (music-theory:fifths-pitch-class (+ f 3)) :mode :minor)
        (music-theory:make-key :tonic (music-theory:fifths-pitch-class f) :mode :major))))

(defun %least-guess (guesses)
  "The (confidence . what) of GUESSES with the least confidence, the first on a
tie, or NIL."
  (let ((best nil))
    (dolist (guess guesses best)
      (when (or (null best) (< (car guess) (car best)))
        (setf best guess)))))

(defun %tempo-bpm (microseconds unit)
  "b = floor(100 * 15000000 / (u * w) + 1/2) / 100, exact."
  (/ (floor (+ (/ (* 100 15000000) (* microseconds unit)) 1/2)) 100))

(defun %import-measures (smf division timed keys &key key meter tempo)
  "(values BARS E): the imported measure map of SMF as %BARs, every slot set,
and E, the end of the last bar. KEYS are the MIDI keys of every imported note
(key detection); KEY, METER and TEMPO the hints (file header)."
  (let* ((w (lambda (tick) (/ tick (* 4 division))))
         (signatures (%last-per-tick timed #'midi-protocol:time-signature-event-p))
         (event0 (cdr (assoc 0 signatures)))
         (at0 (or meter (and event0 (%event-meter event0)) (music-theory:make-meter)))
         (points (cons (cons 0 at0)
                       (loop for (tick . event) in signatures
                             unless (zerop tick)
                               collect (cons (funcall w tick) (%event-meter event)))))
         (bars (%lay-bars (funcall w (%content-end smf)) points))
         (guesses '()))
    (%set-meters bars)
    ;; Keys.
    (let ((events (remove-if-not (lambda (timed) (midi-protocol:key-signature-event-p (cdr timed)))
                                 timed)))
      (loop for (tick . event) in events
            for bar = (%bar-at bars (funcall w tick))
            when bar do (setf (%bar-key bar) (%event-key event)))
      (when bars
        (let* ((b0 (first bars))
               (first-event (cdr (find-if (lambda (timed) (eq b0 (%bar-at bars (funcall w (car timed)))))
                                          events :from-end t)))
               (ranking (and (null first-event)
                             (music-theory:detect-key
                              (music-theory:pitch-class-histogram keys :weight :count))))
               (detected (car (first ranking))))
          (cond (key
                 (setf (%bar-key b0) key)
                 (when (if first-event
                           (or (/= (music-theory:key-signature key)
                                   (midi-protocol:key-signature-event-sharps first-event))
                               (not (eq (eq :minor (music-theory:key-mode key))
                                        (midi-protocol:key-signature-event-minor-p first-event))))
                           (and detected
                                (or (/= (music-theory:pitch-class (music-theory:key-tonic key))
                                        (music-theory:pitch-class (music-theory:key-tonic detected)))
                                    (not (eq (music-theory:key-mode key)
                                             (music-theory:key-mode detected))))))
                   (push (cons +guess-confidence+ "key") guesses)))
                (first-event)
                (detected
                 (setf (%bar-key b0) detected)
                 (push (cons (max 0d0 (min 1d0 (cdr (first ranking)))) "key") guesses))
                (t
                 (setf (%bar-key b0) (music-theory:make-key))
                 (push (cons 0 "key") guesses))))))
    ;; Meter.
    (when (if meter
              (and event0
                   (or (/= (reduce #'+ (music-theory:meter-numerators meter))
                           (midi-protocol:time-signature-event-numerator event0))
                       (/= (music-theory:meter-denominator meter)
                           (midi-protocol:time-signature-event-denominator event0))))
              (null event0))
      (push (cons +guess-confidence+ "meter") guesses))
    (when bars
      (let ((guess (%least-guess guesses)))
        (when guess
          (setf (%bar-confidence (first bars)) (car guess)
                (%bar-what (first bars)) (cdr guess)))))
    ;; Tempo marks.
    (let ((tempi (%last-per-tick timed #'midi-protocol:tempo-event-p)))
      (loop for (tick . event) in tempi
            for x = (funcall w tick)
            for bar = (%bar-at bars x)
            when bar
              do (let ((unit (or (music-theory:beat-unit (%bar-meter bar)) 1/4)))
                   (setf (%bar-tempo bar)
                         (append (%bar-tempo bar)
                                 (list (%make-mark (- x (%bar-start bar))
                                                   (music-theory:make-tempo
                                                    :bpm (%tempo-bpm (midi-protocol:tempo-event-tempo event)
                                                                     unit)
                                                    :beat-unit unit)
                                                   nil))))))
      (when (and tempo bars)
        (let* ((b0 (first bars))
               (event (cdr (assoc 0 tempi)))
               (confidence (and event
                                (/= (%tempo-microseconds tempo)
                                    (midi-protocol:tempo-event-tempo event))
                                +guess-confidence+)))
          (setf (%bar-tempo b0)
                (cons (%make-mark 0 tempo confidence)
                      (remove 0 (%bar-tempo b0) :key #'%mark-offset :test #'=))))))
    ;; Rehearsal marks.
    (loop for (tick . event) in timed
          for bar = (and (midi-protocol:marker-event-p event)
                         (not (%starts-with-p +chord-text-prefix+
                                              (midi-protocol:text-meta-event-text event)))
                         (%bar-at bars (funcall w tick)))
          when (and bar (null (%bar-rehearsal bar)))
            do (setf (%bar-rehearsal bar) (midi-protocol:text-meta-event-text event)))
    (values bars (if bars (%bar-end (car (last bars))) 0))))
