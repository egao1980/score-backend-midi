;;;; SC4 rehearsal sets: one practice file per voice, that voice brought forward.
;;;;
;;;; (REHEARSAL-MIX score voice-id &key (boost 20) (volume 127)
;;;;                (others-volume 80) (others-pan 16))  -> a MIX alist
;;;;   One entry per voice of SCORE, in document order, keyed by the voice id:
;;;;     the voice VOICE-ID   (:velocity BOOST :volume VOLUME :pan 64)
;;;;     every other voice    (:velocity 0 :volume OTHERS-VOLUME :pan OTHERS-PAN)
;;;;   so the chosen voice is louder (note-on velocity + BOOST, CC7 VOLUME) and
;;;;   centred, and the others sit quieter, to one side. BOOST is an integer
;;;;   0..127, VOLUME, OTHERS-VOLUME and OTHERS-PAN integers 0..127 (else
;;;;   TYPE-ERROR). A VOICE-ID that is not the id of a voice of SCORE signals
;;;;   UNKNOWN-ELEMENT (ID = VOICE-ID) inside a USE-VALUE restart whose value, a
;;;;   voice id, is used instead.
;;;;
;;;; (REHEARSAL-SET score &rest keys &key voices boost volume others-volume
;;;;                others-pan &allow-other-keys)
;;;;   -> a fresh list of (VOICE-ID . SMF), one per voice of VOICES (default:
;;;;   every voice of SCORE, in document order; else a list of voice ids, kept
;;;;   in its order). Each SMF is
;;;;     (apply #'score-to-smf score :mix (rehearsal-mix score voice-id ...) rest)
;;;;   where the REHEARSAL-MIX keys are BOOST, VOLUME, OTHERS-VOLUME and
;;;;   OTHERS-PAN as given (their defaults when not), and REST is KEYS without
;;;;   :VOICES, those four keys and :MIX: every SCORE-TO-SMF option but the mix
;;;;   passes through (:DIVISION, :LAYOUT, :PROGRAM, :UNFOLD, :VERSE, ...). A
;;;;   :MIX in KEYS is ignored. Each SCORE-TO-SMF call signals its own warnings.

(in-package #:score-backend-midi)

(defun rehearsal-mix (score voice-id &key (boost 20) (volume 127) (others-volume 80)
                                          (others-pan 16))
  "A SCORE-TO-SMF :MIX that brings the voice VOICE-ID forward (file header)."
  (declare (ignorable score voice-id boost volume others-volume others-pan))
  (%sc4-pending 'rehearsal-mix))

(defun rehearsal-set (score &rest keys &key voices boost volume others-volume others-pan
                      &allow-other-keys)
  "(VOICE-ID . SMF) per voice of VOICES, each with that voice brought forward."
  (declare (ignorable score keys voices boost volume others-volume others-pan))
  (%sc4-pending 'rehearsal-set))
