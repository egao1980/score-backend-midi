;;;; SC4 playback order: repeats, endings and jumps unfolded into the order the
;;;; bars are played.
;;;;
;;;; (PLAYBACK-ORDER score) -> a fresh list of (BAR . PASS) conses, one per bar
;;;; played, in playing order. BAR is a bar number of SCORE (score-protocol
;;;; bars: 0 is a pickup); PASS is how many times that bar has been played up to
;;;; and including this time (1 the first time). A score with no measures gives
;;;; NIL.
;;;;
;;;; These are the rules of score-protocol's SC1 view UNFOLD (0.2.0, contract
;;;; branch agent/sc1-contract-192e), restated so that this backend doesn't wait
;;;; for it: PLAYBACK-ORDER is the source bar and the PASS of every measure of
;;;; (unfold score), in order. Once score-protocol 0.2.0 is published, the
;;;; implementation may call UNFOLD instead; the tests stay as they are. Where
;;;; music21's repeat expansion differs, tests/fixtures/PROVENANCE.md says so.
;;;;
;;;; Ending groups. Endings that each start on the measure after the last
;;;; measure of the one before form a group (an ENDING on bar f covers bars f ..
;;;; f + MEASURES - 1, cut at the last bar). A measure e with REPEAT-END belongs
;;;; to the group that contains e or starts on the bar after e; g(e) is that
;;;; group's last bar, or e when there is none.
;;;;
;;;; Sections. Each measure e with REPEAT-END n ends a section of n passes that
;;;; starts at s(e): the last bar with REPEAT-START in (g(p), e], p the
;;;; REPEAT-END bar before e; when there is none, the bar g(p) + 1. For the
;;;; first section g(p) is taken as the first bar - 1. So a backward repeat with
;;;; no forward repeat goes back to the beginning, or to the bar after the
;;;; section (and its endings) before it.
;;;;
;;;; The walk keeps PASS (the time through the current section, from 1),
;;;; JUMPED (false) and MODE (NIL, :FINE or :CODA), and the jump marks taken. It
;;;; starts at the first bar, and at each bar m:
;;;;   1. When m starts an ending: before a jump it is played when PASS is among
;;;;      its PASSES, after a jump when it is the last ending of its group;
;;;;      otherwise the walk goes on at the bar after the ending's last bar.
;;;;   2. Entering a section start s(e) other than by repeating sets PASS to 1.
;;;;   3. m is played: (m . the number of times m has now been played) is
;;;;      collected.
;;;;   4. At the end of m, the first of these that applies:
;;;;      a. m has REPEAT-END n, not JUMPED, PASS < n: PASS + 1, back to s(m).
;;;;      b. m has a :FINE mark and MODE is :FINE: the walk ends.
;;;;      c. m has a :TO-CODA mark and MODE is :CODA: on at the first bar after
;;;;         m with a :CODA mark; the walk ends when there is none.
;;;;      d. m has a jump mark of kind :DA-CAPO, :DA-CAPO-AL-FINE,
;;;;         :DA-CAPO-AL-CODA, :DAL-SEGNO, :DAL-SEGNO-AL-FINE or
;;;;         :DAL-SEGNO-AL-CODA not taken before (the first such in its JUMP
;;;;         list, which score-protocol keeps in +JUMPS+ order): it is taken,
;;;;         JUMPED becomes true, MODE becomes :FINE for the -AL-FINE kinds,
;;;;         :CODA for the -AL-CODA kinds, NIL for :DA-CAPO and :DAL-SEGNO; the
;;;;         walk goes on at the first bar (D.C.) or at the last bar at or
;;;;         before m with a :SEGNO mark (D.S.).
;;;;      e. on at the next bar; after the last bar the walk ends.
;;;; So repeats come before a jump on the same barline; after a jump repeats
;;;; are not taken again and the last ending of each group is played; a plain
;;;; D.C. or D.S. plays to the end; Fine and To Coda act only after a jump that
;;;; asks for them; every jump mark is taken at most once, so the walk ends.
;;;;
;;;; A D.S. with no :SEGNO mark at or before its bar signals SCORE-ERROR
;;;; (REASON "no segno") with ERROR, inside a CONTINUE restart that ignores the
;;;; jump (the walk goes on as in e).
;;;;
;;;; Examples (tests/playback-test.lisp): "Repeats and Voltas" (bars 1..8) plays
;;;; 1 2 3 4 1 2 5 6 7 6 7 6 8 with passes 1 1 1 1 2 2 1 1 1 2 2 3 1; "Dal Segno
;;;; al Coda" (1..7) plays 1 2 3 4 5 2 3 4 6 7 with passes 1 1 1 1 1 2 2 2 1 1.

(in-package #:score-backend-midi)

(defun playback-order (score)
  "The bars of SCORE in playing order, as (BAR . PASS) conses (file header)."
  (declare (ignorable score))
  (%sc4-pending 'playback-order))
