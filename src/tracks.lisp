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

(defun source-voices (smf)
  "The (TRACK . CHANNEL) voices of SMF that have notes, percussion left out."
  (declare (ignorable smf))
  (%sc4-pending 'source-voices))

(defun melody-voice (smf)
  "The highest monophonic source voice of SMF, and how many are monophonic."
  (declare (ignorable smf))
  (%sc4-pending 'melody-voice))
