;;;; SC4 import, part 3: from an SMF to a score.
;;;;
;;;; (SMF-TO-SCORE smf &key (parts :all) melody key meter tempo (quantize :auto)
;;;;               (subdivisions +subdivisions+) (lyrics t) (chord-symbols t)
;;;;               backend)  -> a SCORE
;;;; (IMPORT-MIDI source &rest keys) reads SOURCE (an octet vector, a binary
;;;;   input stream or a pathname designator) with MIDI-PROTOCOL:READ-SMF and
;;;;   returns (apply #'smf-to-score smf keys). A MIDI-PARSE-ERROR is answered,
;;;;   from a HANDLER-BIND around READ-SMF, by signalling SCORE-FORMAT-ERROR with
;;;;   ERROR (FORMAT :MIDI, POSITION the error's byte offset, CAUSE the
;;;;   MIDI-PARSE-ERROR): midi-protocol's restarts are still in place, so a
;;;;   handler of SCORE-FORMAT-ERROR may invoke USE-PARTIAL-SMF (or SKIP-CHUNK,
;;;;   SKIP-EVENT, USE-VALUE) and the import goes on with what READ-SMF returns.
;;;;   MIDI-FORMAT-WARNINGs pass through.
;;;;
;;;; Arguments (else TYPE-ERROR): SMF an SMF; PARTS and MELODY as in
;;;; tracks.lisp; KEY, METER and TEMPO a music-theory KEY, METER and TEMPO or
;;;; NIL (hints, measures.lisp); QUANTIZE :AUTO, T or NIL; SUBDIVISIONS as for
;;;; QUANTIZE-ONSETS; LYRICS a generalized boolean; CHORD-SYMBOLS T, :EXACT or
;;;; NIL; BACKEND a SAT-BACKEND or NIL, passed to QUANTIZE-ONSETS.
;;;;
;;;; Steps. Notes, source voices and parts: tracks.lisp. The measure map and
;;;; the end E: measures.lisp. Positions are whole notes, tick / (4 * DIVISION).
;;;;
;;;; Beats. Each bar is divided into the beats of its meter (METER-BEATS) laid
;;;; from the bar's start, the last cut at the bar's end; beat k is (START END
;;;; UNIT) as in quantize.lisp, UNIT the beat's full duration. In bar order the
;;;; beats cover 0 .. E.
;;;;
;;;; Quantisation, per voice, of its notes' starts and ends:
;;;;   QUANTIZE :AUTO  the voice is exact when the position x of every start and
;;;;                   end lies on the grid of lcm(SUBDIVISIONS) of its beat
;;;;                   ((x - START) * lcm / UNIT is an integer; x = E counts).
;;;;                   Exact voices are kept, the others snapped.
;;;;   QUANTIZE T      every voice is snapped.
;;;;   QUANTIZE NIL    every voice keeps its positions; no tuplets; no
;;;;                   QUANTIZE-ONSETS call.
;;;; Kept: the CHOICES of (quantize-onsets X beats :exact t :subdivisions
;;;; SUBDIVISIONS :backend BACKEND), X the voice's distinct starts and ends,
;;;; give the tuplets below; positions don't move and q (the quantisation
;;;; confidence) is 1.
;;;; Snapped: (quantize-onsets S beats ...), S the voice's distinct starts in
;;;; ascending order: POSITIONS are the new starts and CONFIDENCES each start's
;;;; q. The voice is single-line when no two of its notes then share a start.
;;;; A note's end: in a single-line voice first cut to the note's next start
;;;; (the next greater snapped start of the voice, or E); then snapped to the
;;;; grid its beat chose (quantize.lisp, Grid; an end at E stays E); when that
;;;; is at or before the snapped start, it becomes the start plus the step of
;;;; the start's beat grid, cut, in a single-line voice, at the next start.
;;;; Then two notes of one key whose spans overlap (one starts before the other
;;;; ends) are one note, from the earlier start to the later end, with the
;;;; earlier note's q; notes that only touch stay apart.
;;;;
;;;; Events. A voice's boundaries are 0, E, and its notes' starts and ends.
;;;; Between two consecutive boundaries a < b, the notes with start <= a and
;;;; end >= b sound: none gives a rest, one a note event, several a chord event
;;;; (chord notes ascending by key). A note sounding in several spans is cut
;;;; into tied pieces. Each span is then cut, in turn:
;;;;   1. at every barline;
;;;;   2. at the start and end of every beat whose choice is a tuplet s
;;;;      (+TUPLET-RATIOS+, ratio r);
;;;;   3. a piece inside such a beat (step h = UNIT / s): one event with TUPLET
;;;;      r when (duration-dots length :tuplet r) is non-NIL, else the longest
;;;;      notatable prefix of whole steps and then the rest, the same way;
;;;;   4. any other piece: one event when (duration-dots length) is non-NIL;
;;;;      else, when its length and its offset in the bar are multiples of
;;;;      1/128, the pieces of (split-duration length :meter M :offset offset
;;;;      :max-dots 1), M the bar's meter; else one event (CHECK-SCORE reports
;;;;      :UNNOTATABLE-DURATION; only QUANTIZE NIL or grids outside
;;;;      SUBDIVISIONS give such lengths).
;;;; A rest that fills its bar is one rest with MEASURE-REST-P T and DURATION
;;;; the bar's length. Each piece of a note but the last holds a TIE whose END
;;;; is the id of the note of the next piece (a note event, or a chord note of
;;;; that key). Every voice has one voice measure per measure.
;;;;
;;;; Spelling (music-theory MT4). A voice's notes, ordered by start and then
;;;; key, are split into runs of consecutive notes whose starts lie in bars of
;;;; one key (BAR-KEY); each run is spelled by (spell-sequence keys :key that
;;;; key), and all pieces of a note carry its pitch (ACCIDENTAL :AUTO).
;;;; AMBIGUOUS-SPELLING reaches the caller with music-theory's restarts. A
;;;; note's spelling confidence sp is 1 when its pitch is in the key (DEGREE-OF
;;;; gives alteration 0 for the :NATURAL or the :HARMONIC variant), else
;;;; 1 - its ambiguity.
;;;;
;;;; Confidence. A note event: min(q, sp) of its note. A chord event: the least
;;;; q of the notes that start at its onset, or of all its notes when none
;;;; does. A chord note: its note's sp. Rests: NIL. Lyrics: 1 when the lyric's
;;;; tick is its note's start tick, else +GUESS-CONFIDENCE+. Chord-symbol
;;;; anchors: NIL when prefixed, +GUESS-CONFIDENCE+ when guessed. Measures,
;;;; tempo marks: measures.lisp. Parts: tracks.lisp. Staves, voices, ties and
;;;; rehearsal marks: NIL.
;;;;
;;;; Lyrics (LYRICS true). Lyric events are the LYRIC-EVENTs of every track,
;;;; and, in a karaoke file (one with a TEXT-EVENT whose text starts with "@K"),
;;;; its TEXT-EVENTs whose text doesn't start with "@". A lyric event belongs to
;;;; the source voice of its track when the track has exactly one, else (none,
;;;; or several: format 0) to the melody (SMF-TO-SCORE :MELODY, else
;;;; MELODY-VOICE); it is left out when that voice isn't imported. Text, per
;;;; kind:
;;;;   LYRIC-EVENT  characters below code 32 removed and spaces trimmed; a
;;;;                trailing "-" marks a syllable that continues its word, and
;;;;                is removed.
;;;;   karaoke      a leading "/" or "\" (line and paragraph breaks) removed;
;;;;                the syllable starts a word when it then starts with a space,
;;;;                had a break, follows a syllable that ended with a space, or
;;;;                is the voice's first; spaces trimmed.
;;;; Empty texts are dropped. Per voice, in tick order (file order, track by
;;;; track, at one tick), SYLLABIC follows from who continues whom, dropped
;;;; lyrics included: a syllable that continues into the next and doesn't
;;;; continue the one before is :BEGIN, one that does both :MIDDLE, one that
;;;; only continues the one before :END, otherwise :SINGLE. Every lyric is
;;;; verse 1 with no extender. It goes on the first piece of the voice's note
;;;; whose start tick is nearest its tick (the earlier note on a tie); when that
;;;; event already has a lyric it is dropped (LOSSY-CONVERSION "lyrics").
;;;;
;;;; Chord symbols. A TEXT-EVENT or MARKER-EVENT whose text starts with
;;;; +CHORD-TEXT-PREFIX+ is an exact chord symbol, unless CHORD-SYMBOLS is NIL:
;;;; (parse-chord-symbol rest :dialect :pop) of the text after the prefix, its
;;;; errors and warnings reaching the caller with music-theory's restarts
;;;; (SKIP-CHORD-SYMBOL drops it). With CHORD-SYMBOLS T, a TEXT-EVENT that is
;;;; not a karaoke lyric and doesn't start with "@" is a guess when it parses
;;;; in the :POP dialect with neither a CHORD-SYMBOL-PARSE-ERROR nor an
;;;; UNKNOWN-CHORD-QUALITY (both are caught there: such text is not a chord).
;;;; Each becomes an anchor at the position of its tick (the bar holding it and
;;;; the offset from its start, exact); of several at one position, the first.
;;;;
;;;; Metadata. :TITLE is the first TRACK-NAME-EVENT text of track 0 when track
;;;; 0 has no notes, else the text after "@T" of a karaoke file's first "@T"
;;;; event; :COPYRIGHT the first COPYRIGHT-EVENT text of track 0.
;;;;
;;;; Provenance and ids. Every element has the provenance (make-provenance
;;;; :source :midi :backend +provenance-backend+). Every element's id is the
;;;; one MAKE-SCORE mints for it in an id-less copy of the result: its kind's
;;;; prefix and its 1-based place in document order, in base 36 (score-protocol
;;;; ids.lisp); SCORE-ID-COUNTER is the number of elements. Equal input gives
;;;; SCORE-EQUAL results.
;;;;
;;;; Losses and guesses. SMF-TO-SCORE WARNs LOSSY-CONVERSION (FORMAT :MIDI) at
;;;; most once per category of +IMPORT-LOSSES+, in that order: "percussion"
;;;; when notes on channel 9 were dropped, "lyrics" when a lyric was. Then,
;;;; once the score is built, it SIGNALs LOW-CONFIDENCE-GUESS for every element
;;;; whose confidence is below +FLAG-BELOW+, in document order: ELEMENT-ID its
;;;; id, CONFIDENCE its confidence, WHAT "quantization" or "spelling" for a
;;;; note event (whichever of q and sp is less, "quantization" on a tie),
;;;; "quantization" for a chord event, "spelling" for a chord note, "meter" or
;;;; "key" for the first measure (the guess with the least confidence, "meter"
;;;; on a tie), "tempo", "chord symbol", "lyric" and "melody" for tempo marks,
;;;; anchors, lyrics and parts. score-protocol's UNCERTAIN-ELEMENTS then lists
;;;; exactly these elements.
;;;;
;;;; Validity. CHECK-SCORE finds no issue in an imported score except
;;;; :UNNOTATABLE-DURATION (step 4 above).

(in-package #:score-backend-midi)

;;; Drafts ---------------------------------------------------------------------------
;;; The import builds the score as these structs first. Every step that signals
;;; (spelling, chord parsing, lyric drops, losses) runs on them, once; the
;;; builder below only calls score-protocol's constructors.

(defstruct (%line (:constructor %make-line (key start end tick q)) (:copier nil) (:predicate nil))
  "A note of an imported voice after quantisation: KEY, START and END (whole
notes), the original start TICK, its quantisation confidence Q, then its PITCH
and spelling confidence SP, and its PIECES (%PIECEs, in time order)."
  key start end tick q pitch sp (pieces '()))

(defstruct (%piece (:constructor %make-piece (line event)) (:copier nil) (:predicate nil))
  "One tied piece of a %LINE: the %EV it sounds in, and NEXT, the next piece."
  line event (next nil))

(defstruct (%ev (:constructor %make-ev (kind onset duration tuplet)) (:copier nil) (:predicate nil))
  "An imported event: KIND :REST, :NOTE or :CHORD, ONSET, DURATION, TUPLET,
MEASURE-REST-P, PIECES (one per sounding note, ascending by key), LYRIC (a
%LYRIC-DRAFT), CONFIDENCE and the WHAT of a guess."
  kind onset duration tuplet (measure-rest-p nil) (pieces '()) (lyric nil)
  (confidence nil) (what nil))

(defstruct (%lyric-draft (:constructor %make-lyric-draft (text syllabic confidence))
                         (:copier nil) (:predicate nil))
  text syllabic confidence)

(defstruct (%voice-draft (:constructor %make-voice-draft (name lines measures))
                         (:copier nil) (:predicate nil))
  "An imported voice: NAME, its %LINEs and MEASURES (a list of lists of %EVs)."
  name lines measures)

(defstruct (%anchor-draft (:constructor %make-anchor-draft (position symbol confidence))
                          (:copier nil) (:predicate nil))
  position symbol confidence)

;;; Beats and quantisation -----------------------------------------------------------

(defun %bar-beats (bar)
  "The beats (START END UNIT) of BAR: its meter's beats from its start, the last
cut at its end (Beats)."
  (let ((end (%bar-end bar)) (position (%bar-start bar)) (out '()))
    (dolist (unit (music-theory:meter-beats (%bar-meter bar)))
      (when (>= position end) (return))
      (push (list position (min (+ position unit) end) unit) out)
      (incf position unit))
    (nreverse out)))

(defun %exact-voice-p (positions beats subdivisions)
  "True when every position lies on the grid of lcm(SUBDIVISIONS) of its beat."
  (let ((lcm (reduce #'lcm subdivisions)))
    (every (lambda (x)
             (let ((beat (nth (%beat-index x beats) beats)))
               (integerp (/ (* (- x (%beat-start beat)) lcm) (%beat-unit beat)))))
           positions)))

(defun %next-start (starts start e)
  "The least of STARTS greater than START, or E."
  (let ((next nil))
    (dolist (s starts (or next e))
      (when (and (> s start) (or (null next) (< s next)))
        (setf next s)))))

(defun %distinct-ascending (numbers)
  "The distinct NUMBERS, ascending, as a fresh list."
  (sort (remove-duplicates (copy-list numbers)) #'<))

(defun %merge-lines (lines)
  "LINES with the notes of one key whose spans overlap joined: the earlier start,
the later end, the earlier note's Q and tick. Sorted by start, then key."
  (let ((out '()))
    (dolist (key (remove-duplicates (mapcar #'%line-key lines)))
      (let ((current nil))
        (dolist (line (stable-sort (copy-list (remove-if-not (lambda (line) (eql key (%line-key line)))
                                                             lines))
                                   #'< :key #'%line-start))
          (cond ((null current) (setf current line))
                ((< (%line-start line) (%line-end current))
                 (setf (%line-end current) (max (%line-end current) (%line-end line))))
                (t (push current out) (setf current line))))
        (when current (push current out))))
    (stable-sort (nreverse out)
                 (lambda (a b) (or (< (%line-start a) (%line-start b))
                                   (and (= (%line-start a) (%line-start b))
                                        (< (%line-key a) (%line-key b))))))))

(defun %voice-lines (notes beats e division quantize subdivisions backend)
  "(values LINES CHOICES): the voice's NOTES quantised (Quantisation), and the
grid choice of every beat (NIL with QUANTIZE NIL)."
  (let* ((w (lambda (tick) (/ tick (* 4 division))))
         (starts (mapcar (lambda (note) (funcall w (%note-start note))) notes))
         (ends (mapcar (lambda (note) (funcall w (%note-end note))) notes))
         (kept (or (null quantize)
                   (and (eq quantize :auto)
                        (%exact-voice-p (append starts ends) beats subdivisions)))))
    (if kept
        (values (%merge-lines
                 (mapcar (lambda (note start end)
                           (%make-line (%note-key note) start end (%note-start note) 1))
                         notes starts ends))
                (and quantize
                     (values (quantize-onsets (%distinct-ascending (append starts ends))
                                              beats :exact t :subdivisions subdivisions
                                              :backend backend))))
        (let ((distinct (%distinct-ascending starts)))
          (multiple-value-bind (choices positions confidences)
              (quantize-onsets distinct beats :subdivisions subdivisions :backend backend)
            (let* ((snapped (mapcar (lambda (start) (nth (position start distinct) positions)) starts))
                   (qs (mapcar (lambda (start) (nth (position start distinct) confidences)) starts))
                   (single (= (length snapped) (length (remove-duplicates snapped)))))
              (values
               (%merge-lines
                (loop for note in notes
                      for start in snapped
                      for q in qs
                      for raw-end in ends
                      collect (let* ((next (%next-start snapped start e))
                                     (end (if single (min raw-end next) raw-end)))
                                (unless (= end e)
                                  (let ((i (%beat-index end beats)))
                                    (setf end (%snap end (nth i beats) (nth i choices)))))
                                (when (<= end start)
                                  (let* ((i (%beat-index start beats))
                                         (stepped (+ start (%grid-step (nth i beats) (nth i choices)))))
                                    (setf end (if single (min stepped next) stepped))))
                                (%make-line (%note-key note) start end (%note-start note) q))))
               choices)))))))

;;; Spelling ---------------------------------------------------------------------------

(defun %bar-keys (bars)
  "The key in force at each bar (BAR-KEY), as a list."
  (let ((key (music-theory:make-key)))
    (mapcar (lambda (bar) (setf key (or (%bar-key bar) key))) bars)))

(defun %spell-lines (lines bars keys)
  "Set the PITCH and SP of LINES (sorted by start, then key) through
MUSIC-THEORY:SPELL-SEQUENCE, one call per run of one key (Spelling)."
  (let ((runs '()))
    (dolist (line lines)
      (let ((key (nth (position (%bar-at bars (%line-start line)) bars) keys)))
        (if (and runs (equalp key (car (first runs))))
            (push line (cdr (first runs)))
            (push (list key line) runs))))
    (dolist (run (nreverse runs))
      (let ((key (car run)) (run-lines (reverse (cdr run))))
        (multiple-value-bind (pitches ambiguities)
            (music-theory:spell-sequence (mapcar #'%line-key run-lines) :key key)
          (loop for line in run-lines
                for pitch in pitches
                for ambiguity in ambiguities
                do (setf (%line-pitch line) pitch
                         (%line-sp line)
                         (if (or (zerop (nth-value 1 (music-theory:degree-of pitch key)))
                                 (zerop (nth-value 1 (music-theory:degree-of pitch key
                                                                             :variant :harmonic))))
                             1
                             (- 1 ambiguity)))))))))

;;; Events -------------------------------------------------------------------------------

(defun %tuplet-lengths (length step ratio)
  "Step 3: LENGTH as one tuplet value, else its longest notatable prefix of whole
STEPs and then the rest, the same way."
  (if (music-theory:duration-dots length :tuplet ratio)
      (list length)
      (let ((prefix (loop for k from (1- (ceiling length step)) downto 1
                          for p = (* k step)
                          when (and (< p length) (music-theory:duration-dots p :tuplet ratio))
                            return p)))
        (if prefix
            (cons prefix (%tuplet-lengths (- length prefix) step ratio))
            (list length)))))

(defun %plain-lengths (length meter offset)
  "Step 4: LENGTH as one value, else SPLIT-DURATION's pieces when it and its bar
OFFSET are multiples of 1/128, else one value."
  (cond ((music-theory:duration-dots length) (list length))
        ((and (integerp (* 128 length)) (integerp (* 128 offset)))
         (music-theory:split-duration length :meter meter :offset offset :max-dots 1))
        (t (list length))))

(defun %tuplet-beats (beats choices)
  "(start end ratio step) of every beat whose choice is a tuplet."
  (loop for beat in beats
        for s in choices
        for ratio = (and s (%beat-tuplet beat s))
        when ratio
          collect (list (%beat-start beat) (%beat-end beat) ratio (%grid-step beat s))))

(defun %event-for (lines onset length tuplet)
  "The %EV for LINES (ascending by key) sounding from ONSET for LENGTH."
  (let ((ev (%make-ev (cond ((null lines) :rest) ((rest lines) :chord) (t :note))
                      onset length tuplet)))
    (setf (%ev-pieces ev)
          (mapcar (lambda (line)
                    (let ((piece (%make-piece line ev)))
                      (push piece (%line-pieces line))
                      piece))
                  lines))
    ev))

(defun %voice-measures (lines bars beats choices)
  "One list of %EVs per bar for the voice's LINES (Events)."
  (let* ((tuplets (%tuplet-beats beats choices))
         (cuts (sort (remove-duplicates
                      (append (list 0)
                              (mapcar #'%bar-start bars) (mapcar #'%bar-end bars)
                              (mapcar #'%line-start lines) (mapcar #'%line-end lines)
                              (mapcar #'first tuplets) (mapcar #'second tuplets)))
                     #'<))
         (measures
           (loop for bar in bars
                 for start = (%bar-start bar)
                 for end = (%bar-end bar)
                 collect
                 (if (notany (lambda (line) (and (< (%line-start line) end) (> (%line-end line) start)))
                             lines)
                     (let ((ev (%make-ev :rest start (%bar-length bar) nil)))
                       (setf (%ev-measure-rest-p ev) t)
                       (list ev))
                     (loop for (a b) on (remove-if-not (lambda (x) (<= start x end)) cuts)
                           while b
                           nconc (let* ((sounding (sort (copy-list
                                                         (remove-if-not
                                                          (lambda (line) (and (<= (%line-start line) a)
                                                                              (>= (%line-end line) b)))
                                                          lines))
                                                        #'< :key #'%line-key))
                                        (tuplet (find-if (lambda (tb) (and (<= (first tb) a)
                                                                           (<= b (second tb))))
                                                         tuplets))
                                        (lengths (if tuplet
                                                     (%tuplet-lengths (- b a) (fourth tuplet) (third tuplet))
                                                     (%plain-lengths (- b a) (%bar-meter bar) (- a start))))
                                        (x a))
                                   (mapcar (lambda (length)
                                             (prog1 (%event-for sounding x length (and tuplet (third tuplet)))
                                               (incf x length)))
                                           lengths)))))))
    ;; Pieces in time order, each tied to the next.
    (dolist (line lines)
      (setf (%line-pieces line) (nreverse (%line-pieces line)))
      (loop for (piece next) on (%line-pieces line)
            do (setf (%piece-next piece) next)))
    ;; Confidences (Confidence).
    (dolist (measure measures)
      (dolist (ev measure)
        (let ((lines (mapcar #'%piece-line (%ev-pieces ev))))
          (case (%ev-kind ev)
            (:note
             (let ((line (first lines)))
               (setf (%ev-confidence ev) (min (%line-q line) (%line-sp line))
                     (%ev-what ev) (if (<= (%line-q line) (%line-sp line)) "quantization" "spelling"))))
            (:chord
             (let ((starting (remove-if-not (lambda (line) (= (%ev-onset ev) (%line-start line))) lines)))
               (setf (%ev-confidence ev) (reduce #'min (or starting lines) :key #'%line-q)
                     (%ev-what ev) "quantization")))))))
    measures))

;;; Lyrics ---------------------------------------------------------------------------------

(defun %karaoke-p (timed)
  (some (lambda (cell) (and (midi-protocol:text-event-p (cdr cell))
                            (%starts-with-p "@K" (midi-protocol:text-meta-event-text (cdr cell)))))
        timed))

(defun %karaoke-lyric-p (event karaoke)
  "True for a karaoke file's TEXT-EVENT that is a lyric."
  (and karaoke
       (midi-protocol:text-event-p event)
       (not (%starts-with-p "@" (midi-protocol:text-meta-event-text event)))))

(defun %clean-lyric (text)
  "(values text continues-p) of a LYRIC-EVENT's TEXT (Lyrics)."
  (let ((clean (string-trim " " (remove-if (lambda (c) (< (char-code c) 32)) text))))
    (if (and (plusp (length clean)) (char= #\- (char clean (1- (length clean)))))
        (values (subseq clean 0 (1- (length clean))) t)
        (values clean nil))))

(defun %lyric-items (smf karaoke)
  "((track tick kind text) ...): the lyric events of SMF in tick order (file
order, track by track, at one tick), KIND :LYRIC or :KARAOKE (Lyrics)."
  (stable-sort
   (loop for track in (midi-protocol:smf-tracks smf)
         for index from 0
         nconc (loop for (tick . event) in (midi-protocol:track-to-absolute track)
                     when (midi-protocol:lyric-event-p event)
                       collect (list index tick :lyric (midi-protocol:text-meta-event-text event))
                     when (%karaoke-lyric-p event karaoke)
                       collect (list index tick :karaoke (midi-protocol:text-meta-event-text event))))
   #'< :key #'second))

(defun %voice-syllables (items)
  "((tick text syllabic) ...) of one voice's lyric ITEMS ((track tick kind raw) ...)."
  (let ((cleaned '()) (previous-space nil) (voice-first t))
    ;; (tick text joined-p starts-word-p kind)
    (dolist (item items)
      (destructuring-bind (track tick kind raw) item
        (declare (ignore track))
        (ecase kind
          (:lyric
           (multiple-value-bind (text continues) (%clean-lyric raw)
             (when (plusp (length text))
               (push (list tick text continues t kind) cleaned)
               (setf voice-first nil))))
          (:karaoke
           (let* ((line-break (and (plusp (length raw)) (find (char raw 0) "/\\")))
                  (body (if line-break (subseq raw 1) raw))
                  (text (string-trim " " body))
                  (starts (or (and (plusp (length body)) (char= #\Space (char body 0)))
                              line-break previous-space voice-first)))
             (when (plusp (length text))
               (push (list tick text nil starts kind) cleaned)
               (setf voice-first nil
                     previous-space (and (plusp (length body))
                                         (char= #\Space (char body (1- (length body))))))))))))
    (let ((rows (coerce (nreverse cleaned) 'simple-vector)))
      ;; A karaoke syllable continues into the next when that one starts no word.
      (loop for i from 0 below (length rows)
            for row = (svref rows i)
            when (eq :karaoke (fifth row))
              do (setf (third row) (and (< (1+ i) (length rows))
                                        (not (fourth (svref rows (1+ i)))))))
      (loop for i from 0 below (length rows)
            for row = (svref rows i)
            for before = (and (plusp i) (third (svref rows (1- i))))
            for after = (third row)
            collect (list (first row) (second row)
                          (cond ((and after (not before)) :begin)
                                ((and after before) :middle)
                                (before :end)
                                (t :single)))))))

(defun %place-lyrics (drafts items losses)
  "Put each syllable of ITEMS on the first piece of the nearest note of the
voice DRAFTS (%VOICE-DRAFTs of one source voice); a syllable whose event
already has one is dropped and records \"lyrics\" in the cell LOSSES."
  (let ((syllables (%voice-syllables items)))
    (dolist (draft drafts)
      (let ((lines (stable-sort (copy-list (%voice-draft-lines draft)) #'< :key #'%line-tick)))
        (when lines
          (loop for (tick text syllabic) in syllables
                for line = (let ((best nil))
                             (dolist (line lines best)
                               (when (or (null best)
                                         (< (abs (- tick (%line-tick line)))
                                            (abs (- tick (%line-tick best)))))
                                 (setf best line))))
                for ev = (%piece-event (first (%line-pieces line)))
                do (if (%ev-lyric ev)
                       (pushnew "lyrics" (car losses) :test #'string=)
                       (setf (%ev-lyric ev)
                             (%make-lyric-draft text syllabic
                                                (if (= tick (%line-tick line)) 1 +guess-confidence+))))))))))

(defun %import-lyrics (smf karaoke notes sources melody division parts losses)
  "Place the lyric events of SMF on the imported voices of PARTS ((plan . drafts)
...): each belongs to its track's source voice when the track has exactly one,
else to the melody (MELODY, else MELODY-VOICE's); it is left out when that
voice isn't imported (Lyrics)."
  (let* ((items (%lyric-items smf karaoke))
         (melody-source nil)
         (melody-known nil))
    (flet ((owner (item)
             (let ((own (remove-if-not (lambda (source) (= (first item) (car source))) sources)))
               (cond ((= 1 (length own)) (first own))
                     (melody-known melody-source)
                     (t (setf melody-known t
                              melody-source (or melody (values (%melody-of notes sources division)))))))))
      (let ((owners (mapcar #'owner items)))
        (dolist (source (remove-duplicates owners :test #'equal :from-end t))
          (when source
            (%place-lyrics
             (loop for (plan . drafts) in parts
                   nconc (loop for voice in (%part-plan-voices plan)
                               for draft in drafts
                               when (equal source (%voice-plan-source voice))
                                 collect draft))
             (loop for item in items
                   for owner in owners
                   when (equal source owner) collect item)
             losses)))))))

;;; Chord symbols, metadata ----------------------------------------------------------------

(defun %bar-position (bars first-bar x)
  "(bar . offset) of the position X, or NIL when no bar holds it."
  (let ((bar (%bar-at bars x)))
    (and bar (cons (+ first-bar (position bar bars)) (- x (%bar-start bar))))))

(defun %guessed-chord (text)
  "TEXT read as a :POP chord symbol, or NIL: such text is not a chord."
  (handler-case (music-theory:parse-chord-symbol text :dialect :pop)
    ((or music-theory:chord-symbol-parse-error music-theory:unknown-chord-quality) () nil)))

(defun %chord-anchors (timed bars first-bar division chord-symbols karaoke)
  "The %ANCHOR-DRAFTs of the chord text in TIMED (Chord symbols)."
  (let ((anchors '()))
    (when chord-symbols
      (loop for (tick . event) in timed
            for text = (and (or (midi-protocol:text-event-p event) (midi-protocol:marker-event-p event))
                            (midi-protocol:text-meta-event-text event))
            when text
              do (multiple-value-bind (symbol confidence)
                     (cond ((%starts-with-p +chord-text-prefix+ text)
                            (values (music-theory:parse-chord-symbol
                                     (subseq text (length +chord-text-prefix+)) :dialect :pop)
                                    nil))
                           ((and (eq chord-symbols t)
                                 (midi-protocol:text-event-p event)
                                 (not (%karaoke-lyric-p event karaoke))
                                 (not (%starts-with-p "@" text)))
                            (values (%guessed-chord text) +guess-confidence+)))
                   (let ((position (and (typep symbol 'music-theory:chord-symbol)
                                        (%bar-position bars first-bar (/ tick (* 4 division))))))
                     (when (and position
                                (not (find position anchors :key #'%anchor-draft-position
                                                            :test #'equal)))
                       (push (%make-anchor-draft position symbol confidence) anchors))))))
    (nreverse anchors)))

(defun %import-metadata (smf notes timed karaoke)
  "The metadata plist (Metadata)."
  (let* ((track0 (first (midi-protocol:smf-tracks smf)))
         (title (or (and track0
                         (notany (lambda (note) (zerop (%note-track note))) notes)
                         (%track-name track0))
                    (and karaoke
                         (loop for (nil . event) in timed
                               when (and (midi-protocol:text-event-p event)
                                         (%starts-with-p "@T" (midi-protocol:text-meta-event-text event)))
                                 return (subseq (midi-protocol:text-meta-event-text event) 2)))))
         (copyright (and track0 (%first-text track0 #'midi-protocol:copyright-event-p))))
    (append (and title (list :title title))
            (and copyright (list :copyright copyright)))))

;;; Building the score -------------------------------------------------------------------------

(defun %build-score (metadata bars parts anchors tie-end)
  "The score of the drafts, every element minted by MAKE-SCORE. TIE-END maps a
%PIECE to the string its tie's END holds. Constructors only: no condition but
theirs."
  (let ((provenance (score-protocol:make-provenance :source :midi :backend +provenance-backend+)))
    (labels ((tie (piece)
               (let ((next (%piece-next piece)))
                 (and next (score-protocol:make-tie :end (funcall tie-end next)
                                                    :provenance provenance))))
             (lyrics (ev)
               (let ((lyric (%ev-lyric ev)))
                 (and lyric
                      (list (score-protocol:make-lyric
                             :text (%lyric-draft-text lyric)
                             :syllabic (%lyric-draft-syllabic lyric)
                             :provenance provenance
                             :confidence (%lyric-draft-confidence lyric))))))
             (event (ev)
               (ecase (%ev-kind ev)
                 (:rest
                  (score-protocol:make-rest-event
                   :duration (%ev-duration ev) :tuplet (%ev-tuplet ev)
                   :measure-rest-p (%ev-measure-rest-p ev) :provenance provenance))
                 (:note
                  (let* ((piece (first (%ev-pieces ev))) (line (%piece-line piece)))
                    (score-protocol:make-note-event
                     :pitch (%line-pitch line) :duration (%ev-duration ev) :tuplet (%ev-tuplet ev)
                     :tie (tie piece) :lyrics (lyrics ev)
                     :provenance provenance :confidence (%ev-confidence ev))))
                 (:chord
                  (score-protocol:make-chord-event
                   :notes (mapcar (lambda (piece)
                                    (let ((line (%piece-line piece)))
                                      (score-protocol:make-chord-note
                                       :pitch (%line-pitch line) :tie (tie piece)
                                       :provenance provenance :confidence (%line-sp line))))
                                  (%ev-pieces ev))
                   :duration (%ev-duration ev) :tuplet (%ev-tuplet ev) :lyrics (lyrics ev)
                   :provenance provenance :confidence (%ev-confidence ev))))))
      (score-protocol:make-score
       :metadata metadata
       :measures
       (loop for (bar . more) on bars
             collect (score-protocol:make-measure-info
                      :time (%bar-time bar) :key (%bar-key bar) :pickup-p (%bar-pickup-p bar)
                      :length (%bar-length-slot bar) :barline (if more :regular :final)
                      :rehearsal (and (%bar-rehearsal bar)
                                      (score-protocol:make-rehearsal-mark
                                       :text (%bar-rehearsal bar) :provenance provenance))
                      :tempo (mapcar (lambda (mark)
                                       (score-protocol:make-tempo-mark
                                        :offset (%mark-offset mark) :tempo (%mark-tempo mark)
                                        :provenance provenance :confidence (%mark-confidence mark)))
                                     (%bar-tempo bar))
                      :provenance provenance :confidence (%bar-confidence bar)))
       :parts
       (mapcar (lambda (part)
                 (destructuring-bind (plan . drafts) part
                   (score-protocol:make-part
                    :name (%part-plan-name plan)
                    :staves (mapcar (lambda (voice)
                                      (score-protocol:make-staff :clef (%voice-plan-clef voice)
                                                                 :provenance provenance))
                                    (%part-plan-voices plan))
                    :voices (loop for draft in drafts
                                  for staff from 1
                                  collect (score-protocol:make-voice
                                           :name (%voice-draft-name draft) :staff staff
                                           :measures (mapcar (lambda (measure) (mapcar #'event measure))
                                                             (%voice-draft-measures draft))
                                           :provenance provenance))
                    :provenance provenance :confidence (%part-plan-confidence plan))))
               parts)
       :chord-symbols
       (mapcar (lambda (anchor)
                 (score-protocol:make-chord-symbol-anchor
                  :position (%anchor-draft-position anchor) :symbol (%anchor-draft-symbol anchor)
                  :provenance provenance :confidence (%anchor-draft-confidence anchor)))
               anchors)))))

(defun %minted-note-ids (parts score whats)
  "A table from each %PIECE of PARTS to the id SCORE (built from them) gave its
note; fills WHATS (id -> WHAT) for the note events."
  (let ((ids (make-hash-table :test 'eq)))
    (loop for (nil . drafts) in parts
          for part in (%seq-list (score-protocol:score-parts score))
          do (loop for draft in drafts
                   for voice in (score-protocol:part-voices part)
                   do (loop for measure in (%voice-draft-measures draft)
                            for events in (%seq-list (score-protocol:voice-measures voice))
                            do (loop for ev in measure
                                     for event in (%seq-list events)
                                     do (case (%ev-kind ev)
                                          (:note
                                           (setf (gethash (first (%ev-pieces ev)) ids)
                                                 (score-protocol:element-id event)
                                                 (gethash (score-protocol:element-id event) whats)
                                                 (%ev-what ev)))
                                          (:chord
                                           (loop for piece in (%ev-pieces ev)
                                                 for note in (score-protocol:chord-event-notes event)
                                                 do (setf (gethash piece ids)
                                                          (score-protocol:element-id note)))))))))
    ids))

(defun %signal-guesses (score whats measure-what)
  "SIGNAL LOW-CONFIDENCE-GUESS for every element of SCORE whose confidence is
below +FLAG-BELOW+, in document order (Losses and guesses)."
  (dolist (element (score-protocol:uncertain-elements score :below +flag-below+))
    (signal 'score-protocol:low-confidence-guess
            :element-id (score-protocol:element-id element)
            :confidence (score-protocol:element-confidence element)
            :what (etypecase element
                    (score-protocol:note-event
                     (gethash (score-protocol:element-id element) whats))
                    (score-protocol:chord-event "quantization")
                    (score-protocol:chord-note "spelling")
                    (score-protocol:measure-info measure-what)
                    (score-protocol:tempo-mark "tempo")
                    (score-protocol:chord-symbol-anchor "chord symbol")
                    (score-protocol:lyric "lyric")
                    (score-protocol:part "melody")))))

;;; Entry points ----------------------------------------------------------------------------------

(defun %parts-p (object)
  "SMF-TO-SCORE :PARTS: :ALL, :MELODY or a list of track indices and (TRACK . CHANNEL)s."
  (or (member object '(:all :melody))
      (%proper-list-of-p object (lambda (element)
                                  (typep element '(or (integer 0) (cons (integer 0) (integer 0 15))))))))

(defun smf-to-score (smf &key (parts :all) melody key meter tempo (quantize :auto)
                              (subdivisions +subdivisions+) (lyrics t) (chord-symbols t)
                              backend)
  "A score from the midi-protocol SMF SMF (file header)."
  (check-type smf midi-protocol:smf)
  (check-type parts (satisfies %parts-p) ":ALL, :MELODY or a list of tracks and (track . channel)s")
  (check-type melody (or null (integer 0) (cons (integer 0) (integer 0 15))))
  (check-type key (or null music-theory:key))
  (check-type meter (or null music-theory:meter))
  (check-type tempo (or null music-theory:tempo))
  (check-type quantize (member :auto t nil))
  (check-type subdivisions (satisfies %subdivisions-p)
              "a non-empty list of distinct members of +SUBDIVISIONS+")
  (check-type chord-symbols (member t :exact nil))
  (check-type backend (or null sat-protocol:sat-backend))
  (let* ((division (%division smf))
         (smf-tracks (midi-protocol:smf-tracks smf))
         (notes (%smf-notes smf))
         (sources (%sources-of notes))
         (melody (%melody-source melody sources))
         (plans (multiple-value-bind (groups confidence)
                    (%part-groups parts melody notes sources division smf-tracks)
                  (%plan-parts groups confidence notes smf-tracks)))
         (timed (%merged-timed smf))
         (karaoke (%karaoke-p timed))
         (losses (list '())))
    (multiple-value-bind (bars e)
        (%import-measures smf division timed
                          (loop for plan in plans
                                nconc (loop for voice in (%part-plan-voices plan)
                                            nconc (mapcar #'%note-key (%voice-plan-notes voice))))
                          :key key :meter meter :tempo tempo)
      (let* ((first-bar (if (and bars (%bar-pickup-p (first bars))) 0 1))
             (beats (loop for bar in bars append (%bar-beats bar)))
             (keys (%bar-keys bars))
             (parts (mapcar
                     (lambda (plan)
                       (cons plan
                             (mapcar (lambda (voice)
                                       (multiple-value-bind (lines choices)
                                           (%voice-lines (%voice-plan-notes voice) beats e division
                                                         quantize subdivisions backend)
                                         (%spell-lines lines bars keys)
                                         (%make-voice-draft (%voice-plan-name voice) lines
                                                            (%voice-measures lines bars beats choices))))
                                     (%part-plan-voices plan))))
                     plans)))
        (when lyrics
          (%import-lyrics smf karaoke notes sources melody division parts losses))
        (let ((anchors (%chord-anchors timed bars first-bar division chord-symbols karaoke))
              (metadata (%import-metadata smf notes timed karaoke)))
          (when (some #'%percussion-p notes)
            (push "percussion" (car losses)))
          (%warn-losses (car losses) +import-losses+)
          ;; Ids: MAKE-SCORE mints them in an id-less build; a second build gives
          ;; every tie the id its target got in the first.
          (let* ((whats (make-hash-table :test 'equal))
                 (rough (%build-score metadata bars parts anchors (constantly "x")))
                 (ids (%minted-note-ids parts rough whats))
                 (score (%build-score metadata bars parts anchors
                                      (lambda (piece) (gethash piece ids)))))
            (assert (= (score-protocol:score-id-counter rough) (score-protocol:score-id-counter score))
                    () "The two builds of one draft minted different ids.")
            (%signal-guesses score whats (and bars (%bar-what (first bars))))
            score))))))

(defun import-midi (source &rest keys)
  "Read SOURCE with midi-protocol's READ-SMF, then SMF-TO-SCORE with KEYS."
  (apply #'smf-to-score
         (handler-bind ((midi-protocol:midi-parse-error
                          (lambda (c)
                            (error 'score-protocol:score-format-error
                                   :format :midi
                                   :position (midi-protocol:midi-parse-error-offset c)
                                   :reason (midi-protocol:midi-error-reason c)
                                   :cause c))))
           (midi-protocol:read-smf source))
         keys))
