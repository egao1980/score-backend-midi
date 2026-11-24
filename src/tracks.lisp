;;;; SC4 import, part 1: notes, source voices, the melody and the parts.
;;;;
;;;; Notes. Ticks are read per track with MIDI-PROTOCOL:TRACK-TO-ABSOLUTE. A
;;;; NOTE-ON-EVENT with velocity > 0 starts a note; it ends at the first later
;;;; NOTE-OFF-EVENT, or NOTE-ON-EVENT with velocity 0, of the same channel and
;;;; key in the same track that doesn't already end an earlier note (first in,
;;;; first out). A note still sounding at the track's last tick ends there.
;;;; Notes whose end tick equals their start tick are dropped, and so are
;;;; note-offs that end nothing. A note is (TRACK CHANNEL KEY START END
;;;; VELOCITY), START and END ticks.
;;;;
;;;; (SOURCE-VOICES smf) -> a fresh list of (TRACK . CHANNEL) conses: every
;;;; track (its 0-based index in SMF-TRACKS) and channel with at least one
;;;; note, ascending by track and then channel, leaving out channel 9 (GM
;;;; percussion; SMF-TO-SCORE warns "percussion" when it drops such notes).
;;;; Format 0 is no special case: its one track gives one source voice per
;;;; channel.
;;;;
;;;; Monophonic. A source voice is monophonic when no two of its notes start
;;;; less than DIVISION/8 ticks apart (a 32nd note): the notes of a chord start
;;;; together, legato overlaps don't count.
;;;;
;;;; (MELODY-VOICE smf) -> (values VOICE CANDIDATES). VOICE is the monophonic
;;;; source voice with the greatest mean key (the exact mean of its notes'
;;;; keys), the earliest in SOURCE-VOICES order on a tie; when none is
;;;; monophonic, the source voice with the greatest mean key; NIL when there is
;;;; no source voice. CANDIDATES is the number of monophonic source voices.
;;;;
;;;; Parts, from SMF-TO-SCORE's :PARTS:
;;;;   :ALL (default)  every source voice. The tracks that hold source voices are
;;;;                   grouped, in order: a run of consecutive such tracks whose
;;;;                   first INSTRUMENT-NAME-EVENT texts are equal and not empty
;;;;                   is one part; any other track is a part of its own. A part's
;;;;                   voices are its tracks' source voices, in SOURCE-VOICES order.
;;;;   :MELODY         one part with one voice, the melody: SMF-TO-SCORE's
;;;;                   :MELODY when given, else MELODY-VOICE's VOICE (no part when
;;;;                   that is NIL).
;;;;   a list          one part per element, in order: a track index (one part
;;;;                   with that track's source voices) or a (TRACK . CHANNEL)
;;;;                   cons (one part with that source voice). An element that
;;;;                   names no source voice gives no part.
;;;; SMF-TO-SCORE's :MELODY is NIL, a track index (its first source voice) or a
;;;; (TRACK . CHANNEL) source voice; one naming no source voice is a TYPE-ERROR.
;;;; It also chooses where lyrics without a voice of their own go (import.lisp).
;;;;
;;;; Names. A part is named by its first track's first INSTRUMENT-NAME-EVENT
;;;; text when that isn't empty, else by its first track's first
;;;; TRACK-NAME-EVENT text, else NIL. A voice is named by its track's first
;;;; TRACK-NAME-EVENT text when its part spans more than one track, else NIL.
;;;; Staves. A part has one staff per voice, voice i (1-based) on staff i, with
;;;; clef :TREBLE when the mean key of that voice's notes is at least 60, else
;;;; :BASS. Voices have no stem direction.
;;;; Confidence. A part's is NIL, except under :PARTS :MELODY with no :MELODY
;;;; given and CANDIDATES other than 1: +GUESS-CONFIDENCE+ (the melody was a
;;;; choice among several lines, or a guess among none).

(in-package #:score-backend-midi)

(defparameter +percussion-channel+ 9
  "The GM percussion channel, whose notes are never a source voice. Data.")

;;; Notes ----------------------------------------------------------------------------

(defstruct (%note (:constructor %make-note (track channel key start end velocity))
                  (:copier nil) (:predicate nil))
  "A note of the file (Notes): TRACK index, CHANNEL, KEY, START and END ticks."
  track channel key start end velocity)

(defun %track-notes (track index)
  "The notes of TRACK, number INDEX, in note-on order (Notes): first in, first
out per channel and key; a note still sounding at the track's last tick ends
there; zero-length notes and note-offs that end nothing are dropped."
  (let ((open (make-hash-table :test 'equal)) (notes '()) (last 0))
    (dolist (timed (midi-protocol:track-to-absolute track))
      (destructuring-bind (tick . event) timed
        (setf last tick)
        (multiple-value-bind (key velocity)
            (typecase event
              (midi-protocol:note-on-event
               (values (midi-protocol:note-on-event-key event)
                       (midi-protocol:note-on-event-velocity event)))
              (midi-protocol:note-off-event
               (values (midi-protocol:note-off-event-key event) 0)))
          (when key
            (let ((cell (cons (midi-protocol:channel-event-channel event) key)))
              (if (plusp velocity)
                  (let ((note (%make-note index (car cell) key tick nil velocity)))
                    (push note notes)
                    (setf (gethash cell open) (nconc (gethash cell open) (list note))))
                  (let ((note (pop (gethash cell open))))
                    (when note (setf (%note-end note) tick)))))))))
    (dolist (note notes)
      (unless (%note-end note) (setf (%note-end note) last)))
    (remove-if (lambda (note) (= (%note-start note) (%note-end note))) (nreverse notes))))

(defun %smf-notes (smf)
  "Every note of SMF, track by track."
  (loop for track in (midi-protocol:smf-tracks smf)
        for index from 0
        append (%track-notes track index)))

(defun %note-source (note)
  (cons (%note-track note) (%note-channel note)))

(defun %percussion-p (note)
  (= +percussion-channel+ (%note-channel note)))

(defun %sources-of (notes)
  "The source voices of NOTES: distinct (track . channel), percussion left out,
ascending by track and then channel."
  (sort (remove-duplicates (mapcar #'%note-source (remove-if #'%percussion-p notes))
                           :test #'equal)
        (lambda (a b) (or (< (car a) (car b))
                          (and (= (car a) (car b)) (< (cdr a) (cdr b)))))))

(defun %source-notes (notes source)
  "The notes of NOTES on the source voice SOURCE, in order."
  (remove-if-not (lambda (note) (equal source (%note-source note))) notes))

(defun %mean-key (notes)
  "The exact mean of the keys of NOTES."
  (/ (reduce #'+ notes :key #'%note-key) (length notes)))

(defun %monophonic-p (notes division)
  "True when no two of NOTES start less than DIVISION/8 ticks apart (Monophonic)."
  (let ((starts (sort (mapcar #'%note-start notes) #'<)))
    (loop for (a b) on starts
          while b
          always (>= (- b a) (/ division 8)))))

(defun %melody-of (notes sources division)
  "(values VOICE CANDIDATES) of MELODY-VOICE for NOTES and their SOURCES."
  (let* ((means (mapcar (lambda (source) (%mean-key (%source-notes notes source))) sources))
         (mono (mapcar (lambda (source) (%monophonic-p (%source-notes notes source) division))
                       sources))
         (candidates (count t mono))
         (best nil) (best-mean nil))
    (loop for source in sources
          for mean in means
          for monophonic in mono
          when (and (or monophonic (zerop candidates))
                    (or (null best) (> mean best-mean)))
            do (setf best source best-mean mean))
    (values best candidates)))

(defun source-voices (smf)
  "The (TRACK . CHANNEL) voices of SMF that have notes, percussion left out."
  (check-type smf midi-protocol:smf)
  (%sources-of (%smf-notes smf)))

(defun melody-voice (smf)
  "The highest monophonic source voice of SMF, and how many are monophonic."
  (check-type smf midi-protocol:smf)
  (let ((notes (%smf-notes smf)))
    (%melody-of notes (%sources-of notes) (%division smf))))

;;; Parts ----------------------------------------------------------------------------

(defstruct (%voice-plan (:constructor %make-voice-plan (source name clef notes))
                        (:copier nil) (:predicate nil))
  "An imported voice: its SOURCE (track . channel), NAME, CLEF and NOTES."
  source name clef notes)

(defstruct (%part-plan (:constructor %make-part-plan (name voices confidence))
                       (:copier nil) (:predicate nil))
  "An imported part: its NAME, %VOICE-PLANs and CONFIDENCE."
  name voices confidence)

(defun %first-text (track predicate)
  "The text of TRACK's first meta event that satisfies PREDICATE, or NIL."
  (let ((event (find-if predicate track)))
    (and event (midi-protocol:text-meta-event-text event))))

(defun %instrument-name (track)
  (%first-text track #'midi-protocol:instrument-name-event-p))

(defun %track-name (track)
  (%first-text track #'midi-protocol:track-name-event-p))

(defun %melody-type (sources)
  "The type a :MELODY of these SOURCES must have."
  (let ((tracks (remove-duplicates (mapcar #'car sources))))
    `(or null (member ,@tracks) (cons (member ,@tracks) (integer 0 15)))))

(defun %melody-source (melody sources)
  "The source voice MELODY names (SMF-TO-SCORE :MELODY): its first source voice
for a track index, itself for a (TRACK . CHANNEL), NIL for NIL. One that names
no source voice is a TYPE-ERROR inside a STORE-VALUE restart (checked again)."
  (loop
    (let ((source (typecase melody
                    (null (return nil))
                    (integer (find melody sources :key #'car))
                    (cons (find melody sources :test #'equal)))))
      (when source (return source))
      (restart-case (error 'type-error :datum melody :expected-type (%melody-type sources))
        (store-value (value)
          :report "Use another melody (checked again)."
          :interactive (lambda ()
                         (format *query-io* "~&Melody: ")
                         (finish-output *query-io*)
                         (list (read *query-io*)))
          (setf melody value))))))

(defun %part-groups (parts melody notes sources division smf-tracks)
  "(values GROUPS CONFIDENCE): the source voices of each part PARTS asks for,
and the confidence of the parts (Parts, Confidence). MELODY is the resolved
SMF-TO-SCORE :MELODY source voice, or NIL."
  (ecase (if (listp parts) :list parts)
    (:all
     (let ((groups '()))
       ;; A run of consecutive tracks with one non-empty instrument name.
       (dolist (track (remove-duplicates (mapcar #'car sources) :from-end t))
         (let ((name (%instrument-name (nth track smf-tracks))))
           (if (and groups
                    (plusp (length name))
                    (equal name (%instrument-name (nth (first (first groups)) smf-tracks))))
               (push track (first groups))
               (push (list track) groups))))
       (values (mapcar (lambda (group)
                         (remove-if-not (lambda (source) (member (car source) group)) sources))
                       (nreverse groups))
               nil)))
    (:melody
     (multiple-value-bind (voice candidates)
         (if melody (values melody 1) (%melody-of notes sources division))
       (values (and voice (list (list voice)))
               (and (null melody) (/= candidates 1) +guess-confidence+))))
    (:list
     (values (loop for element in parts
                   for group = (if (consp element)
                                   (and (member element sources :test #'equal) (list element))
                                   (remove-if-not (lambda (source) (= element (car source)))
                                                  sources))
                   when group collect group)
             nil))))

(defun %plan-parts (groups confidence notes smf-tracks)
  "A %PART-PLAN per group of source voices (Names, Staves, Confidence)."
  (mapcar (lambda (group)
            (let* ((tracks (remove-duplicates (mapcar #'car group) :from-end t))
                   (first-track (nth (first tracks) smf-tracks))
                   (instrument (%instrument-name first-track)))
              (%make-part-plan
               (if (plusp (length instrument)) instrument (%track-name first-track))
               (mapcar (lambda (source)
                         (let ((source-notes (%source-notes notes source)))
                           (%make-voice-plan source
                                             (and (rest tracks)
                                                  (%track-name (nth (car source) smf-tracks)))
                                             (if (>= (%mean-key source-notes) 60) :treble :bass)
                                             source-notes)))
                       group)
               confidence)))
          groups))
