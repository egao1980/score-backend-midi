;;;; score-backend-midi: score-protocol scores to and from Standard MIDI Files.
;;;; Brief: cl-stack/docs/capabilities/score.md, slice SC4. The SMF values are
;;;; midi-protocol's (SMF, events, READ-SMF, WRITE-SMF); pitches, keys, meters,
;;;; tempi and chord symbols are music-theory's; the score is score-protocol's.
;;;;
;;;; Files:
;;;;   tables.lisp     the data the rules name (velocities, channels, weights)
;;;;   export.lisp     SCORE-TO-SMF, EXPORT-MIDI: score -> SMF type 1, repeats
;;;;                   unfolded by score-protocol's UNFOLD
;;;;   mix.lisp        REHEARSAL-MIX, REHEARSAL-SET: one practice file per voice
;;;;   quantize.lisp   QUANTIZE-ONSETS: the per-beat grid, via sat-protocol
;;;;   tracks.lisp     SOURCE-VOICES, MELODY-VOICE, the track -> part mapping
;;;;   measures.lisp   the imported measure map: meter, key, tempo, hints
;;;;   import.lisp     SMF-TO-SCORE, IMPORT-MIDI: events, spelling, text, confidence
;;;;
;;;; Conditions. score-protocol owns the types; this backend signals them and
;;;; defines none of its own (CLHS 9):
;;;;   LOSSY-CONVERSION   WARN, FORMAT :MIDI, once per category that applies
;;;;                      (+EXPORT-LOSSES+ for export, +IMPORT-LOSSES+ for
;;;;                      import); MUFFLE-WARNING as for every warning.
;;;;   LOW-CONFIDENCE-GUESS  SIGNAL (silent unless handled), once per imported
;;;;                      element whose confidence is below +FLAG-BELOW+.
;;;;   UNKNOWN-ELEMENT    export: a :PROGRAMS or :MIX key that is not the id of
;;;;                      a part or voice of the score; ERROR inside CONTINUE,
;;;;                      which ignores that entry.
;;;;   INVALID-POSITION   export: an :UNFOLD entry whose bar is not a bar of the
;;;;                      score; ERROR inside CONTINUE, which drops the entry.
;;;;   SCORE-ERROR        export: whatever UNFOLD signals (a D.S. with no segno).
;;;;   SCORE-FORMAT-ERROR import, FORMAT :MIDI: a MIDI-PARSE-ERROR from READ-SMF
;;;;                      (CAUSE that condition, POSITION its byte offset),
;;;;                      signalled from a handler while midi-protocol's restarts
;;;;                      (USE-PARTIAL-SMF, SKIP-CHUNK, SKIP-EVENT, USE-VALUE)
;;;;                      are still established; and an SMPTE division (REASON
;;;;                      "SMPTE division"), inside USE-VALUE whose value, an
;;;;                      integer 1..32767, is used as ticks per quarter note.
;;;; Conditions of the libraries below reach the caller with their own
;;;; restarts: music-theory's AMBIGUOUS-SPELLING (SIGNAL; USE-VALUE,
;;;; MUFFLE-WARNING), CHORD-SYMBOL-PARSE-ERROR (USE-VALUE, SKIP-CHORD-SYMBOL)
;;;; and UNKNOWN-CHORD-QUALITY for prefixed chord text, sat-protocol's
;;;; SAT-NO-BACKEND (USE-BACKEND, USE-VALUE), midi-protocol's
;;;; MIDI-FORMAT-WARNING and MIDI-ENCODE-ERROR. Argument errors are TYPE-ERRORs
;;;; from CHECK-TYPE (STORE-VALUE).

(defpackage #:score-backend-midi
  (:use #:cl)
  (:documentation "score-protocol scores to and from Standard MIDI Files (slice SC4).

Export: SCORE-TO-SMF returns a midi-protocol SMF of format 1 (a conductor track,
then one track per voice or per part, one channel per voice), EXPORT-MIDI writes
it; repeats, endings and jumps are played as score-protocol's UNFOLD orders them.
REHEARSAL-MIX and REHEARSAL-SET make practice files that bring one voice forward.

Import: SMF-TO-SCORE builds a score from an SMF, IMPORT-MIDI from bytes, a
stream or a file. QUANTIZE-ONSETS is the per-beat grid choice (through
sat-protocol:minimize); SOURCE-VOICES and MELODY-VOICE expose the track mapping.
Every imported element has provenance :MIDI; guesses carry a confidence below 1,
so score-protocol:uncertain-elements is the uncertainty report.")
  (:export
   ;; Data (tables.lisp)
   #:+default-division+ #:+default-program+ #:+midi-channels+
   #:+default-volume+ #:+default-pan+ #:+dynamic-velocities+
   #:+chord-text-prefix+ #:+subdivisions+ #:+grid-weights+ #:+tuplet-ratios+
   #:+export-losses+ #:+import-losses+ #:+flag-below+ #:+guess-confidence+
   #:+provenance-backend+ #:+spelling-rule-confidence+
   ;; Export (export.lisp, mix.lisp)
   #:score-to-smf #:export-midi
   #:rehearsal-mix #:rehearsal-set
   ;; Import (quantize.lisp, tracks.lisp, measures.lisp, import.lisp)
   #:quantize-onsets
   #:source-voices #:melody-voice
   #:smf-to-score #:import-midi))

(in-package #:score-backend-midi)
