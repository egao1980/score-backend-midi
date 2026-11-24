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

(defparameter +rehearsal-mix-keys+ '(:boost :volume :others-volume :others-pan)
  "The REHEARSAL-SET keys that are REHEARSAL-MIX's. Data.")

(defun %plist-select (plist keep-p)
  "A fresh plist of the key/value pairs of PLIST whose key satisfies KEEP-P, in order."
  (loop for (key value) on plist by #'cddr
        when (funcall keep-p key)
          nconc (list key value)))

(defun rehearsal-mix (score voice-id &key (boost 20) (volume 127) (others-volume 80)
                                          (others-pan 16))
  "A SCORE-TO-SMF :MIX that brings the voice VOICE-ID forward (file header)."
  (check-type score score-protocol:score)
  (check-type boost (integer 0 127))
  (check-type volume (integer 0 127))
  (check-type others-volume (integer 0 127))
  (check-type others-pan (integer 0 127))
  (let ((ids (mapcar #'score-protocol:element-id (%score-voices score))))
    (loop until (member voice-id ids :test #'equal)
          do (restart-case (error 'score-protocol:unknown-element :id voice-id)
               (use-value (value)
                 :report "Use another voice id (checked again)."
                 :interactive (lambda ()
                                (format *query-io* "~&Voice id: ")
                                (finish-output *query-io*)
                                (list (read-line *query-io*)))
                 (setf voice-id value))))
    (mapcar (lambda (id)
              (if (equal id voice-id)
                  (list id :velocity boost :volume volume :pan 64)
                  (list id :velocity 0 :volume others-volume :pan others-pan)))
            ids)))

(defun rehearsal-set (score &rest keys &key voices boost volume others-volume others-pan
                      &allow-other-keys)
  "(VOICE-ID . SMF) per voice of VOICES, each with that voice brought forward."
  (declare (ignore boost volume others-volume others-pan))
  (check-type score score-protocol:score)
  (check-type voices list)
  (let ((mix-keys (%plist-select keys (lambda (key) (member key +rehearsal-mix-keys+))))
        (rest (%plist-select keys (lambda (key)
                                    (not (or (member key +rehearsal-mix-keys+)
                                             (member key '(:voices :mix))))))))
    (mapcar (lambda (voice-id)
              (cons voice-id
                    (apply #'score-to-smf score
                           :mix (apply #'rehearsal-mix score voice-id mix-keys)
                           rest)))
            (or voices (mapcar #'score-protocol:element-id (%score-voices score))))))
