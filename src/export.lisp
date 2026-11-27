;;;; SC4 export: a score as a Standard MIDI File of format 1.
;;;;
;;;; (SCORE-TO-SMF score &key (division +default-division+) (layout :voice)
;;;;               (program +default-program+) programs mix (unfold t) (verse 1)
;;;;               (chord-symbols :text) (default-dynamic :mf))  -> an SMF
;;;; (EXPORT-MIDI score destination &rest keys) is
;;;;   (midi-protocol:write-smf (apply #'score-to-smf score keys) destination)
;;;;   with WRITE-SMF's DESTINATION (NIL for a fresh octet vector, a binary
;;;;   stream, a pathname designator) and return value.
;;;;
;;;; Arguments (else TYPE-ERROR, from CHECK-TYPE):
;;;;   DIVISION        ticks per quarter note, an integer 1..32767.
;;;;   LAYOUT          :VOICE (one track per voice) or :PART (one per part).
;;;;   PROGRAM         the program-change byte 0..127 of every voice.
;;;;   PROGRAMS        an alist (id . program): a voice id, or a part id for all
;;;;                   its voices. A voice's own entry wins over its part's.
;;;;   MIX             an alist (id . plist), ids as for PROGRAMS, plist keys
;;;;                   :VELOCITY (an integer -127..127 added to every note-on
;;;;                   velocity, default 0), :VOLUME (CC7 0..127, default
;;;;                   +DEFAULT-VOLUME+) and :PAN (CC10 0..127, default
;;;;                   +DEFAULT-PAN+). A voice uses its own entry, else its
;;;;                   part's, else none; each missing key takes its default.
;;;;   UNFOLD          T (below), NIL, or a list of entries, each a bar number
;;;;                   (pass 1) or a (bar . pass) cons.
;;;;   VERSE           NIL (no lyrics), an integer >= 1, or :PASS.
;;;;   CHORD-SYMBOLS   :TEXT, :MARKER or NIL.
;;;;   DEFAULT-DYNAMIC a dynamic of +DYNAMIC-VELOCITIES+ whose AFTER isn't NIL.
;;;; Keys of PROGRAMS and MIX are looked up with EQUAL. A key that is not the
;;;; id of a part or voice of SCORE signals UNKNOWN-ELEMENT (ID = the key) with
;;;; ERROR inside a CONTINUE restart that ignores the entry. An UNFOLD entry
;;;; whose bar isn't a bar of SCORE (score-first-bar .. score-last-bar) signals
;;;; INVALID-POSITION (POSITION = the entry) inside a CONTINUE restart that drops
;;;; the entry. SCORE is not validated: CHECK-SCORE issues don't stop an export.
;;;; The entries name SCORE's bars (score-first-bar .. score-last-bar).
;;;;
;;;; Playing order. Repeats, endings and jumps are score-protocol's (SC1): with
;;;; UNFOLD T the export plays S = (score-protocol:unfold score), every bar of
;;;; that view once in order, each with the PASS that UNFOLD's third value gives
;;;; its measure. Its SCORE-ERROR (a D.S. with no segno) reaches the caller.
;;;; With UNFOLD NIL, S is SCORE and every bar is played once in written order,
;;;; pass 1; with a list, S is SCORE and its bars are played in the order and
;;;; with the passes the entries give. Below, the rules read S; the parts,
;;;; voices and their ids are the same in SCORE and its view, so PROGRAMS and
;;;; MIX apply to both.
;;;;
;;;; Timeline. The played bars P_0 .. P_n-1 of S are the (BAR . PASS) entries
;;;; above. P_j starts at U_j = the sum of the BAR-LENGTHs of the bars of P_0 ..
;;;; P_j-1, and U = U_n is the end. A position x (whole notes from U_0 = 0) is at
;;;; tick T(x) = floor(4 * DIVISION * x + 1/2). Every position is computed
;;;; exactly and rounded once, never by summing rounded lengths.
;;;;
;;;; Voices and channels. Voices are numbered k = 0, 1, ... in document order
;;;; (parts in order, each part's voices in order). Voice k plays on channel
;;;; (nth (mod k 15) +midi-channels+). Part i (1-based) is labelled by its
;;;; PART-NAME, or "Part i" when it has none. A voice is labelled by its
;;;; VOICE-NAME; else by its part's label when the part has one voice; else by
;;;; "<part label> <j>", j its 1-based place in the part ("Piano 2").
;;;;
;;;; Tracks. (make-smf :format 1 :division DIVISION :tracks ...): track 0 is
;;;; the conductor track; then LAYOUT :VOICE gives track k + 1 to voice k, and
;;;; :PART gives track i to part i (1-based), holding all of its voices. Every
;;;; track is built with MIDI-PROTOCOL:TRACK-FROM-ABSOLUTE from timed events in
;;;; the order stated below, so events at one tick keep that order, and ends
;;;; with one END-OF-TRACK-EVENT at T(U).
;;;;
;;;; The conductor track, in this order at any one tick:
;;;;   1. At tick 0: a TRACK-NAME-EVENT with the metadata :TITLE, then a
;;;;      COPYRIGHT-EVENT with :COPYRIGHT, each when the score has it.
;;;;   2. TIME-SIGNATURE-EVENT at T(U_j) for every played bar j whose signature
;;;;      differs from bar j-1's, and for j = 0. A bar's signature: with M its
;;;;      BAR-TIME and L its BAR-LENGTH, the sum of M's numerators over M's
;;;;      denominator when L is (meter-measure-duration M); otherwise L written
;;;;      over the smallest power of two d >= M's denominator for which L * d is
;;;;      an integer (a 1/4 pickup in 3/4 is 1/4, a final half bar of 3/4 is
;;;;      2/4, a 1/8 pickup in 6/8 is 1/8). CLOCKS-PER-CLICK is
;;;;      max(1, floor(96 * u)), u = (beat-unit (make-meter :numerators (list
;;;;      numerator) :denominator denominator)): 24 in 4/4 and 2/4, 36 in 6/8,
;;;;      12 in 3/8 and 1/8. THIRTY-SECONDS-PER-QUARTER is 8.
;;;;   3. KEY-SIGNATURE-EVENT at T(U_j) for every played bar j whose BAR-KEY
;;;;      isn't EQUALP to bar j-1's, and for j = 0: SHARPS (key-signature key),
;;;;      MINOR-P true for a :MINOR key.
;;;;   4. TEMPO-EVENT. First, at tick 0, +DEFAULT-TEMPO+ (500000) when the
;;;;      first played bar has no tempo mark with a TEMPO at offset 0. Then, for
;;;;      every played bar j and each of its tempo marks with a TEMPO (BPM b of
;;;;      BEAT-UNIT u), in TEMPO order: at T(U_j + OFFSET), the microseconds per
;;;;      quarter note floor(15000000 / (b * u) + 1/2) (a float b through
;;;;      RATIONALIZE), clamped to 1..16777215. Text-only marks give nothing.
;;;;   5. MARKER-EVENT at T(U_j) with the TEXT of the REHEARSAL mark of every
;;;;      played bar j that has one.
;;;;   6. CHORD-SYMBOLS :TEXT or :MARKER: for every played bar j, each anchor of
;;;;      that bar in track order, at T(U_j + offset), a TEXT-EVENT or a
;;;;      MARKER-EVENT whose text is +CHORD-TEXT-PREFIX+ followed by
;;;;      (print-chord-symbol symbol :dialect :pop).
;;;; Events of one kind at one tick come in played-bar order, then mark order.
;;;;
;;;; A voice's track (LAYOUT :VOICE), in this order at any one tick:
;;;;   1. At tick 0: TRACK-NAME-EVENT (the voice's label), INSTRUMENT-NAME-EVENT
;;;;      (its part's label), then on its channel PROGRAM-CHANGE-EVENT, and
;;;;      CONTROL-CHANGE-EVENTs for controller 7 (volume) and 10 (pan), MIX
;;;;      values.
;;;;   2. NOTE-OFF-EVENTs (velocity 0), ascending by key.
;;;;   3. LYRIC-EVENTs.
;;;;   4. NOTE-ON-EVENTs, ascending by key.
;;;; A part's track (LAYOUT :PART): at tick 0 TRACK-NAME-EVENT and
;;;; INSTRUMENT-NAME-EVENT both with the part's label, then for each of its
;;;; voices in order its program change, CC7 and CC10; at every tick the
;;;; note-offs of all its voices (ascending by channel, then key), their lyrics
;;;; (in voice order), and their note-ons (ascending by channel, then key).
;;;;
;;;; Notes. A voice's playback sequence is, for every played bar j in order,
;;;; the events of its voice measure for that bar (index bar - first bar; a
;;;; missing voice measure is silent, one past the measure map is never
;;;; played) that are not grace events, each at onset U_j + its offset (the
;;;; durations of the non-grace events before it in the voice measure). Rests
;;;; sound nothing. A note event sounds its pitch, a chord event each of its
;;;; chord notes (two chord notes with one MIDI key sound once, the first). A
;;;; note's key is (pitch-midi (note-pitch n)); one outside 0..127 isn't written.
;;;; Ties: a note n (a note event or a chord note) continues into the next
;;;; event of the playback sequence when that event starts at n's end (onset +
;;;; duration) and is, or holds, the note whose id is (tie-end (note-tie n)),
;;;; with n's key. A chain of continuations sounds once, from its first note's
;;;; onset to its last note's end, with its first note's velocity. Each sounding
;;;; note gives a NOTE-ON-EVENT at T(onset) and a NOTE-OFF-EVENT, velocity 0, at
;;;; T(end), or at T(onset) + 1 when rounding made T(end) <= T(onset).
;;;;
;;;; Velocity. Per voice a dynamic in force runs along the playback sequence
;;;; (rests included), starting at DEFAULT-DYNAMIC. An event with a DYNAMIC d
;;;; gives its notes d's VELOCITY (+DYNAMIC-VELOCITIES+); after it, d's AFTER is
;;;; in force unless AFTER is NIL (an accent: sf, sfz, fz, rf, rfz). Other events
;;;; give the VELOCITY of the dynamic in force. Then the mix :VELOCITY is added
;;;; and the result clamped to 1..127. Hairpins, articulations and fermatas
;;;; change neither velocity nor timing.
;;;;
;;;; Lyrics. VERSE v (an integer): every sounding event (a note or chord event)
;;;; of the playback sequence with a lyric of verse v gives a LYRIC-EVENT at
;;;; T(onset), continued notes included. VERSE :PASS: v is the PASS of the
;;;; played bar. VERSE NIL: no lyrics. The text is the lyric's TEXT, followed by
;;;; "-" when its SYLLABIC is :BEGIN or :MIDDLE. Extenders are not written.
;;;;
;;;; Losses. After building the SMF and before returning it, SCORE-TO-SMF WARNs
;;;; LOSSY-CONVERSION (FORMAT :MIDI) once per category that applies, in
;;;; +EXPORT-LOSSES+ order, WHAT = its string:
;;;;   "ids"              always: ids, provenance and confidence have no place
;;;;                      in an SMF;
;;;;   "grace notes"      a grace event in a played bar (none is written);
;;;;   "tick rounding"    a position written whose 4 * DIVISION * x is not an
;;;;                      integer (bar starts, note ends, lyrics, tempo, chords);
;;;;   "pitch range"      a sounding note outside MIDI 0..127;
;;;;   "tempo range"      a tempo clamped to 1..16777215;
;;;;   "shared channels"  more than 15 voices.
;;;; The rest of the notation (slurs, hairpins, articulations, fermatas, breath
;;;; marks, extenders, stems, clefs, accidental display, tuplets, measure
;;;; numbers, jumps and endings once unfolded, metadata other than title and
;;;; copyright, text-only tempo marks, the verses not chosen) is dropped without
;;;; a warning.

(in-package #:score-backend-midi)

;;; Small helpers shared by every file -------------------------------------------

(defun %proper-list-of-p (object predicate)
  "True when OBJECT is a proper list whose members satisfy PREDICATE."
  (loop for tail = object then (cdr tail)
        while (consp tail)
        always (funcall predicate (car tail))
        finally (return (null tail))))

(defun %seq-list (seq)
  "The members of SEQ (an FSet seq or a list) as a list."
  (fset:convert 'list seq))

(defun %score-voices (score)
  "Every voice of SCORE, in document order."
  (loop for part in (%seq-list (score-protocol:score-parts score))
        append (score-protocol:part-voices part)))

(defun %event-notes (event)
  "The notes EVENT sounds: itself for a note event, its chord notes for a chord."
  (typecase event
    (score-protocol:note-event (list event))
    (score-protocol:chord-event (score-protocol:chord-event-notes event))
    (t '())))

(defun %grace-event-p (event)
  (and (typep event 'score-protocol:sounding-event) (score-protocol:event-grace event) t))

(defun %warn-losses (losses table &key (format :midi) (direction :to))
  "WARN LOSSY-CONVERSION (FORMAT, default :MIDI; DIRECTION, default :TO) once for
each string of TABLE in LOSSES, in TABLE order."
  (dolist (what table)
    (when (member what losses :test #'string=)
      (warn 'score-protocol:lossy-conversion :format format :direction direction :what what))))

;;; Arguments ------------------------------------------------------------------

(defun %programs-p (object)
  "An alist (id . program), each program 0..127."
  (%proper-list-of-p object (lambda (entry)
                              (and (consp entry) (typep (cdr entry) '(integer 0 127))))))

(defun %mix-plist-p (object)
  "A plist of :VELOCITY -127..127, :VOLUME 0..127 and :PAN 0..127."
  (and (listp object)
       (loop for tail = object then (cddr tail)
             until (null tail)
             always (and (consp tail) (consp (cdr tail))
                         (case (car tail)
                           (:velocity (typep (cadr tail) '(integer -127 127)))
                           ((:volume :pan) (typep (cadr tail) '(integer 0 127)))
                           (t nil))))))

(defun %mix-p (object)
  "An alist (id . plist) of mix entries."
  (%proper-list-of-p object (lambda (entry)
                              (and (consp entry) (%mix-plist-p (cdr entry))))))

(defun %unfold-entry-p (object)
  (or (integerp object)
      (and (consp object) (integerp (car object)) (typep (cdr object) '(integer 1)))))

(defun %unfold-p (object)
  "T, NIL, or a list of bars and (bar . pass) conses."
  (or (eq object t)
      (%proper-list-of-p object #'%unfold-entry-p)))

(defun %level-dynamic-p (object)
  "A dynamic of +DYNAMIC-VELOCITIES+ whose AFTER isn't NIL."
  (and (third (assoc object +dynamic-velocities+)) t))

(defun %known-entries (alist ids)
  "The entries of ALIST whose key is one of IDS. Any other entry signals
UNKNOWN-ELEMENT (ID = its key) inside a CONTINUE restart that ignores it."
  (remove-if-not (lambda (entry)
                   (or (member (car entry) ids :test #'equal)
                       (restart-case (error 'score-protocol:unknown-element :id (car entry))
                         (continue ()
                           :report "Ignore this entry."
                           nil))))
                 alist))

(defun %part-and-voice-ids (score)
  (loop for part in (%seq-list (score-protocol:score-parts score))
        collect (score-protocol:element-id part)
        append (mapcar #'score-protocol:element-id (score-protocol:part-voices part))))

;;; Playing order ----------------------------------------------------------------

(defun %played-bars (score unfold)
  "(values S PLAYED): the score played and its (bar . pass) entries (Playing order)."
  (cond ((eq unfold t)
         (multiple-value-bind (view id-map passes) (score-protocol:unfold score)
           (declare (ignore id-map))
           (values view
                   (loop for measure in (%seq-list (score-protocol:score-measure-map view))
                         for bar from (score-protocol:score-first-bar view)
                         collect (cons bar (values (fset:lookup passes
                                                                (score-protocol:element-id measure))))))))
        ((null unfold)
         (values score
                 (loop for bar from (score-protocol:score-first-bar score)
                         to (score-protocol:score-last-bar score)
                       collect (cons bar 1))))
        (t
         (let ((first (score-protocol:score-first-bar score))
               (last (score-protocol:score-last-bar score)))
           (values score
                   (loop for entry in unfold
                         for cell = (if (consp entry) (cons (car entry) (cdr entry)) (cons entry 1))
                         when (or (<= first (car cell) last)
                                  (restart-case (error 'score-protocol:invalid-position
                                                       :position entry
                                                       :reason "not a bar of the score")
                                    (continue ()
                                      :report "Drop this entry."
                                      nil)))
                           collect cell))))))

;;; Conductor ------------------------------------------------------------------

(defun %played-signature (s bar)
  "(numerator . denominator) of BAR's time signature (conductor, 2)."
  (let ((meter (score-protocol:bar-time s bar))
        (length (score-protocol:bar-length s bar)))
    (if (= length (music-theory:meter-measure-duration meter))
        (cons (reduce #'+ (music-theory:meter-numerators meter))
              (music-theory:meter-denominator meter))
        (loop for d = (music-theory:meter-denominator meter) then (* 2 d)
              when (integerp (* length d))
                return (cons (* length d) d)))))

(defun %clocks-per-click (numerator denominator)
  (max 1 (floor (* 96 (music-theory:beat-unit
                       (music-theory:make-meter :numerators (list numerator)
                                                :denominator denominator))))))

(defun %tempo-microseconds (tempo)
  "floor(15000000 / (b * u) + 1/2) for TEMPO, a float BPM through RATIONALIZE."
  (floor (+ (/ 15000000 (* (rationalize (music-theory:tempo-bpm tempo))
                           (music-theory:tempo-beat-unit tempo)))
            1/2)))

;;; Timed rows -------------------------------------------------------------------
;;; A row is ((tick cat sub1 sub2 seq) . event): the order the file header
;;; states at one tick is CAT (the numbered kinds), then SUB1 SUB2 (channel and
;;; key, or the voice number), then SEQ, the order of emission.

(defun %row-key< (a b)
  (loop for x in a
        for y in b
        do (cond ((< x y) (return t))
                 ((> x y) (return nil)))
        finally (return nil)))

(defun %track-of (rows end-tick)
  "A track of ROWS, in key order, ending with one END-OF-TRACK-EVENT at
END-TICK (or at the last event, when that is later)."
  (midi-protocol:track-from-absolute
   (cons (cons end-tick (midi-protocol:make-end-of-track-event))
         (mapcar (lambda (row) (cons (first (car row)) (cdr row)))
                 (stable-sort (copy-list rows) #'%row-key< :key #'car)))))

;;; Voices -----------------------------------------------------------------------

(defstruct (%play (:constructor %make-play (onset event pass)) (:copier nil) (:predicate nil))
  "One event of a voice's playback sequence: its ONSET (whole notes from 0),
the EVENT, and the PASS of its played bar."
  onset event pass)

(defstruct (%voice-out (:constructor %make-voice-out) (:copier nil) (:predicate nil))
  "What one voice writes: its number K, part index I (0-based), CHANNEL, labels,
program and mix values, NOTES ((on off key velocity) ...) sorted by on then key,
and LYRICS ((tick text) ...) in playback order."
  k i channel label part-label program volume pan notes lyrics)

(defun %playback (s voice played starts losses)
  "VOICE's playback sequence along PLAYED as a simple-vector of %PLAY (Notes).
Grace events are left out, recording \"grace notes\" in the cell LOSSES."
  (let ((measures (%seq-list (score-protocol:voice-measures voice)))
        (count (fset:size (score-protocol:score-measure-map s)))
        (first (score-protocol:score-first-bar s))
        (out '()))
    (loop for (bar . pass) in played
          for u in starts
          for index = (- bar first)
          when (and (< index (length measures)) (< index count))
            do (let ((offset 0))
                 (dolist (event (%seq-list (nth index measures)))
                   (if (%grace-event-p event)
                       (pushnew "grace notes" (car losses) :test #'string=)
                       (progn (push (%make-play (+ u offset) event pass) out)
                              (incf offset (score-protocol:event-duration event)))))))
    (coerce (nreverse out) 'simple-vector)))

(defun %velocities (plays default-dynamic boost)
  "The note-on velocity of each %PLAY: the dynamic in force along the sequence
(rests included), accents, then BOOST added and the result clamped (Velocity)."
  (let ((level default-dynamic))
    (map 'simple-vector
         (lambda (play)
           (let* ((mark (score-protocol:event-dynamic (%play-event play)))
                  (row (and mark (assoc (score-protocol:dynamic-mark-value mark)
                                        +dynamic-velocities+)))
                  (velocity (if row
                                (second row)
                                (second (assoc level +dynamic-velocities+)))))
             (when (and row (third row))
               (setf level (third row)))
             (max 1 (min 127 (+ velocity boost)))))
         plays)))

(defun %sounding-key (note)
  (music-theory:pitch-midi (score-protocol:note-pitch note)))

(defun %sounding-notes (plays velocities tick losses)
  "((on off key velocity) ...) of the sounding notes of PLAYS, each tie chain
once, in playback order (Notes, Ties). TICK writes a position."
  (let ((continued (make-hash-table :test 'equal))
        (out '()))
    (dotimes (i (length plays) (nreverse out))
      (let ((play (svref plays i)) (seen '()))
        (dolist (note (%event-notes (%play-event play)))
          (let ((key (%sounding-key note)))
            (unless (member key seen)
              (push key seen)
              (unless (gethash (cons i (score-protocol:element-id note)) continued)
                (let ((stop (+ (%play-onset play)
                               (score-protocol:event-duration (%play-event play))))
                      (current note)
                      (ci i))
                  (loop for tie = (score-protocol:note-tie current)
                        while (and tie (< (1+ ci) (length plays)))
                        do (let* ((next (svref plays (1+ ci)))
                                  (target (find (score-protocol:tie-end tie)
                                                (%event-notes (%play-event next))
                                                :key #'score-protocol:element-id
                                                :test #'equal)))
                             (unless (and target
                                          (= stop (%play-onset next))
                                          (= key (%sounding-key target)))
                               (return))
                             (setf (gethash (cons (1+ ci) (score-protocol:element-id target))
                                            continued)
                                   t)
                             (setf stop (+ (%play-onset next)
                                           (score-protocol:event-duration (%play-event next)))
                                   current target
                                   ci (1+ ci))))
                  (if (<= 0 key 127)
                      (let* ((on (funcall tick (%play-onset play)))
                             (off (funcall tick stop)))
                        (when (<= off on) (setf off (1+ on)))
                        (push (list on off key (svref velocities i)) out))
                      (pushnew "pitch range" (car losses) :test #'string=)))))))))))

(defun %lyric-text (lyric)
  (if (member (score-protocol:lyric-syllabic lyric) '(:begin :middle))
      (concatenate 'string (score-protocol:lyric-text lyric) "-")
      (score-protocol:lyric-text lyric)))

(defun %voice-lyrics (plays verse tick)
  "((tick text) ...) of the lyrics VERSE selects along PLAYS (Lyrics)."
  (when verse
    (loop for play across plays
          for event = (%play-event play)
          for v = (if (eq verse :pass) (%play-pass play) verse)
          unless (typep event 'score-protocol:rest-event)
            append (loop for lyric in (score-protocol:event-lyrics event)
                         when (eql v (score-protocol:lyric-verse lyric))
                           collect (list (funcall tick (%play-onset play))
                                         (%lyric-text lyric))))))

(defun %voice-outs (s played starts programs mix program verse default-dynamic tick losses)
  "A %VOICE-OUT per voice of S, in document order (Voices and channels, Notes,
Velocity, Lyrics)."
  (let ((k -1) (outs '()))
    (loop for part in (%seq-list (score-protocol:score-parts s))
          for i from 0
          for part-label = (or (score-protocol:part-name part) (format nil "Part ~D" (1+ i)))
          for voices = (score-protocol:part-voices part)
          do (loop for voice in voices
                   for j from 1
                   for voice-id = (score-protocol:element-id voice)
                   for part-id = (score-protocol:element-id part)
                   for prog = (or (assoc voice-id programs :test #'equal)
                                  (assoc part-id programs :test #'equal))
                   for entry = (cdr (or (assoc voice-id mix :test #'equal)
                                        (assoc part-id mix :test #'equal)))
                   for plays = (%playback s voice played starts losses)
                   for velocities = (%velocities plays default-dynamic (getf entry :velocity 0))
                   do (incf k)
                      (push (%make-voice-out
                             :k k :i i
                             :channel (nth (mod k 15) +midi-channels+)
                             :label (or (score-protocol:voice-name voice)
                                        (if (= 1 (length voices))
                                            part-label
                                            (format nil "~A ~D" part-label j)))
                             :part-label part-label
                             :program (if prog (cdr prog) program)
                             :volume (getf entry :volume +default-volume+)
                             :pan (getf entry :pan +default-pan+)
                             :notes (stable-sort (%sounding-notes plays velocities tick losses)
                                                 (lambda (a b)
                                                   (or (< (first a) (first b))
                                                       (and (= (first a) (first b))
                                                            (< (third a) (third b))))))
                             :lyrics (%voice-lyrics plays verse tick))
                            outs)))
    (nreverse outs)))

(defun %voice-track (outs name instrument end-tick)
  "The track of the voices OUTS (one voice, or a part's), named NAME and
INSTRUMENT (Tracks: setup, note-offs, lyrics, note-ons)."
  (let ((rows '()) (seq -1))
    (flet ((put (tick cat sub1 sub2 event)
             (push (cons (list tick cat sub1 sub2 (incf seq)) event) rows)))
      (put 0 1 0 0 (midi-protocol:make-track-name-event :text name))
      (put 0 1 0 0 (midi-protocol:make-instrument-name-event :text instrument))
      (dolist (out outs)
        (let ((channel (%voice-out-channel out)))
          (put 0 1 0 0 (midi-protocol:make-program-change-event
                        :channel channel :program (%voice-out-program out)))
          (put 0 1 0 0 (midi-protocol:make-control-change-event
                        :channel channel :controller 7 :value (%voice-out-volume out)))
          (put 0 1 0 0 (midi-protocol:make-control-change-event
                        :channel channel :controller 10 :value (%voice-out-pan out)))))
      (dolist (out outs)
        (let ((channel (%voice-out-channel out)))
          (loop for (on off key velocity) in (%voice-out-notes out)
                do (put off 2 channel key (midi-protocol:make-note-off-event
                                           :channel channel :key key :velocity 0))
                   (put on 4 channel key (midi-protocol:make-note-on-event
                                          :channel channel :key key :velocity velocity)))
          (loop for (tick text) in (%voice-out-lyrics out)
                do (put tick 3 (%voice-out-k out) 0 (midi-protocol:make-lyric-event :text text))))))
    (%track-of rows end-tick)))

(defun %conductor-track (s played starts chord-symbols tick losses end-tick)
  "Track 0 (The conductor track, 1-6)."
  (let ((rows '()) (seq -1) (metadata (score-protocol:score-metadata s)))
    (flet ((put (at cat event)
             (push (cons (list at cat 0 0 (incf seq)) event) rows)))
      ;; 1. Title and copyright.
      (let ((title (getf metadata :title)) (copyright (getf metadata :copyright)))
        (when title (put 0 1 (midi-protocol:make-track-name-event :text title)))
        (when copyright (put 0 1 (midi-protocol:make-copyright-event :text copyright))))
      ;; 2. Time signatures.
      (loop with previous = nil
            for (bar) in played
            for u in starts
            for j from 0
            for signature = (%played-signature s bar)
            do (when (or (zerop j) (not (equal signature previous)))
                 (destructuring-bind (n . d) signature
                   (put (funcall tick u) 2
                        (midi-protocol:make-time-signature-event
                         :numerator n :denominator d
                         :clocks-per-click (%clocks-per-click n d)
                         :thirty-seconds-per-quarter 8))))
               (setf previous signature))
      ;; 3. Key signatures.
      (loop with previous = nil
            for (bar) in played
            for u in starts
            for j from 0
            for key = (score-protocol:bar-key s bar)
            do (when (or (zerop j) (not (equalp key previous)))
                 (put (funcall tick u) 3
                      (midi-protocol:make-key-signature-event
                       :sharps (music-theory:key-signature key)
                       :minor-p (eq :minor (music-theory:key-mode key)))))
               (setf previous key))
      ;; 4. Tempi.
      (when (and played
                 (notany (lambda (mark)
                           (and (score-protocol:tempo-mark-tempo mark)
                                (zerop (score-protocol:tempo-mark-offset mark))))
                         (score-protocol:measure-info-tempo
                          (score-protocol:bar-measure s (car (first played))))))
        (put 0 4 (midi-protocol:make-tempo-event :tempo midi-protocol:+default-tempo+)))
      (loop for (bar) in played
            for u in starts
            do (dolist (mark (score-protocol:measure-info-tempo (score-protocol:bar-measure s bar)))
                 (let ((tempo (score-protocol:tempo-mark-tempo mark)))
                   (when tempo
                     (let ((us (%tempo-microseconds tempo)))
                       (unless (<= 1 us 16777215)
                         (pushnew "tempo range" (car losses) :test #'string=)
                         (setf us (max 1 (min 16777215 us))))
                       (put (funcall tick (+ u (score-protocol:tempo-mark-offset mark))) 4
                            (midi-protocol:make-tempo-event :tempo us)))))))
      ;; 5. Rehearsal markers.
      (loop for (bar) in played
            for u in starts
            for mark = (score-protocol:measure-info-rehearsal (score-protocol:bar-measure s bar))
            when mark
              do (put (funcall tick u) 5
                      (midi-protocol:make-marker-event
                       :text (score-protocol:rehearsal-mark-text mark))))
      ;; 6. Chord symbols.
      (when chord-symbols
        (let ((anchors (%seq-list (score-protocol:score-chord-symbols s))))
          (loop for (bar) in played
                for u in starts
                do (dolist (anchor anchors)
                     (let ((position (score-protocol:anchor-position anchor)))
                       (when (eql bar (car position))
                         (let ((text (concatenate 'string +chord-text-prefix+
                                                  (music-theory:print-chord-symbol
                                                   (score-protocol:anchor-symbol anchor)
                                                   :dialect :pop))))
                           (put (funcall tick (+ u (cdr position))) 6
                                (if (eq chord-symbols :marker)
                                    (midi-protocol:make-marker-event :text text)
                                    (midi-protocol:make-text-event :text text))))))))))
      (%track-of rows end-tick))))

;;; Entry points -------------------------------------------------------------------

(defun score-to-smf (score &key (division +default-division+) (layout :voice)
                                (program +default-program+) programs mix (unfold t)
                                (verse 1) (chord-symbols :text) (default-dynamic :mf))
  "SCORE as a midi-protocol SMF of format 1 (file header)."
  (check-type score score-protocol:score)
  (check-type division (integer 1 32767))
  (check-type layout (member :voice :part))
  (check-type program (integer 0 127))
  (check-type programs (satisfies %programs-p) "an alist (id . program 0..127)")
  (check-type mix (satisfies %mix-p)
              "an alist (id . plist of :VELOCITY -127..127, :VOLUME and :PAN 0..127)")
  (check-type unfold (satisfies %unfold-p) "T, NIL or a list of bars and (bar . pass) conses")
  (check-type verse (or null (integer 1) (eql :pass)))
  (check-type chord-symbols (member :text :marker nil))
  (check-type default-dynamic (satisfies %level-dynamic-p)
              "a dynamic of +DYNAMIC-VELOCITIES+ that is not an accent")
  (let* ((ids (%part-and-voice-ids score))
         (programs (%known-entries programs ids))
         (mix (%known-entries mix ids))
         (losses (list (list "ids"))))
    (multiple-value-bind (s played) (%played-bars score unfold)
      (let* ((starts (loop with u = 0
                           for (bar) in played
                           collect u
                           do (incf u (score-protocol:bar-length s bar))))
             (end (reduce #'+ played :key (lambda (cell) (score-protocol:bar-length s (car cell)))))
             (end-tick (floor (+ (* 4 division end) 1/2)))
             (tick (lambda (x)
                     (let ((v (* 4 division x)))
                       (unless (integerp v)
                         (pushnew "tick rounding" (car losses) :test #'string=))
                       (floor (+ v 1/2)))))
             (conductor (%conductor-track s played starts chord-symbols tick losses end-tick))
             (outs (%voice-outs s played starts programs mix program verse default-dynamic
                                tick losses))
             (tracks (ecase layout
                       (:voice
                        (mapcar (lambda (out)
                                  (%voice-track (list out) (%voice-out-label out)
                                                (%voice-out-part-label out) end-tick))
                                outs))
                       (:part
                        (loop for i from 0 below (fset:size (score-protocol:score-parts s))
                              for part-outs = (remove-if-not (lambda (out) (= i (%voice-out-i out)))
                                                             outs)
                              for label = (or (score-protocol:part-name
                                               (fset:@ (score-protocol:score-parts s) i))
                                              (format nil "Part ~D" (1+ i)))
                              collect (%voice-track part-outs label label end-tick)))))
             (smf (midi-protocol:make-smf :format 1 :division division
                                          :tracks (cons conductor tracks))))
        (when (> (length outs) 15)
          (pushnew "shared channels" (car losses) :test #'string=))
        (%warn-losses (car losses) +export-losses+)
        smf))))

(defun export-midi (score destination &rest keys)
  "Write SCORE-TO-SMF of SCORE and KEYS to DESTINATION with midi-protocol's WRITE-SMF."
  (midi-protocol:write-smf (apply #'score-to-smf score keys) destination))
