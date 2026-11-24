;;;; SC4 quantisation: a grid per beat, chosen through sat-protocol.
;;;;
;;;; (QUANTIZE-ONSETS onsets beats &key (subdivisions +subdivisions+) exact backend)
;;;;   -> (values CHOICES POSITIONS CONFIDENCES)
;;;;
;;;; Arguments (else TYPE-ERROR):
;;;;   ONSETS        a list of rationals (whole notes).
;;;;   BEATS         a non-empty list of beats, each a list (START END UNIT) of
;;;;                 rationals with 0 < END - START <= UNIT, contiguous (each
;;;;                 START is the END before it). Every onset o lies in one beat:
;;;;                 START <= o < END, or o = END of the last beat.
;;;;   SUBDIVISIONS  a non-empty list of distinct members of +SUBDIVISIONS+.
;;;;   EXACT         a generalized boolean (below).
;;;;   BACKEND       a SAT-BACKEND or NIL (SAT-PROTOCOL:*SAT-BACKEND*).
;;;; Results, fresh lists:
;;;;   CHOICES       one subdivision count s per beat, in beat order (with
;;;;                 EXACT, NIL for a beat that no allowed grid fits).
;;;;   POSITIONS     one per onset, in ONSETS order: the onset snapped to the
;;;;                 grid its beat chose (with EXACT, the onset itself).
;;;;   CONFIDENCES   one rational 0..1 per onset, in ONSETS order.
;;;;
;;;; Grid. A beat (START END UNIT) divided by s has the step h = UNIT / s and
;;;; the points START + k * h, k = 0, 1, ..., that are below END, plus END. A
;;;; full beat (END = START + UNIT) has s + 1 points; a beat cut short by a
;;;; barline keeps its step. Snapping a position x in the beat to s gives the
;;;; point nearest to x, the later of two equally near; its deviation is
;;;; |x - point|. The import snaps note ends the same way (import.lisp).
;;;;
;;;; Kinds. A beat is :DOTTED when the numerator of UNIT in lowest terms is 3
;;;; (3/8, 3/4, 3/16), else :SIMPLE. s is a tuplet subdivision of the beat when
;;;; +TUPLET-RATIOS+ lists it under the beat's kind (simple: 3 and 6, ratio 3/2;
;;;; dotted: 2, 4 and 8, ratio 2/3), else natural.
;;;;
;;;; Cost. With D, L and T the :DEVIATION, :LEVEL and :TUPLET of +GRID-WEIGHTS+:
;;;;   cost(b, s) = sum over the onsets o of beat b of floor(D * dev(o, s) / UNIT + 1/2)
;;;;                + L * omega(s) + T * (1 if s is a tuplet of b, else 0)
;;;; where omega(s) counts the prime factors of s with multiplicity (1: 0, 2: 1,
;;;; 3: 1, 4: 2, 6: 2, 8: 3). The first term is onset deviation in thousandths
;;;; of a beat, the rest notation complexity (brief: "cost = onset deviation +
;;;; notation complexity"). The weights were set on humanised renderings
;;;; (tests/fixtures/PROVENANCE.md): coarse natural grids first, a triplet
;;;; before a grid two levels finer.
;;;;
;;;; Choice. A beat may choose every s of SUBDIVISIONS; with EXACT, only the s
;;;; whose grid holds every onset of the beat (deviation 0), and when none does
;;;; the beat's choice is NIL. Each beat takes the allowed s of least cost, the
;;;; one earliest in SUBDIVISIONS on a tie. Beats are independent, so these
;;;; choices are the unique optimum of
;;;;   variables  g(b, s) for every beat b and allowed s;
;;;;   hard       exactly one g(b, s) per beat with an allowed s;
;;;;   objective  (:lex O1 O2), O1 = sum cost(b, s) g(b, s),
;;;;              O2 = sum rank(s) g(b, s), rank(s) = s's 0-based index in
;;;;              SUBDIVISIONS,
;;;; and QUANTIZE-ONSETS finds it with SAT-PROTOCOL:MINIMIZE, passing BACKEND:
;;;; the grid choice is a selection problem, so it goes through the logic family
;;;; (rules-and-logic). How the problem is cut into MINIMIZE calls (one, or one
;;;; per beat) is free, and a beat without onsets may be settled without one
;;;; (its cost is the complexity alone); but at least one MINIMIZE call is made
;;;; whenever some beat holds an onset, and SAT-PROTOCOL:SAT-NO-BACKEND then
;;;; reaches the caller when neither BACKEND nor *SAT-BACKEND* is set.
;;;;
;;;; Confidence. For a beat b, its margin is m(b) = min(1, (c2 - c1) / L): c1
;;;; the least cost of b, c2 the least cost of the other subdivisions b may
;;;; choose, L the :LEVEL weight; m(b) = 1 when b may choose only one. An
;;;; onset o of b snapped with step h to the point p has the confidence
;;;;   min(1 - (2 |o - p| / h)^2, m(b))
;;;; exactly: 1 on the grid of a clear choice, 0 midway between two points or
;;;; when two subdivisions cost the same. So an onset is uncertain when it sits
;;;; far from its point, or when another grid read the beat nearly as well (a
;;;; late note that a finer grid catches). With EXACT every confidence is 1.

(in-package #:score-backend-midi)

(defun quantize-onsets (onsets beats &key (subdivisions +subdivisions+) exact backend)
  "Choose a subdivision per beat of BEATS for ONSETS and snap them (file header):
(values choices positions confidences)."
  (declare (ignorable onsets beats subdivisions exact backend))
  (%sc4-pending 'quantize-onsets))
