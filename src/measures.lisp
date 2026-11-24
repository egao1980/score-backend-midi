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
