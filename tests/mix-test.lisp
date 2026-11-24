;;;; SC4 rehearsal sets (src/mix.lisp): the brief's ":mix velocity and volume
;;;; per voice". Expected values by hand from the rules and the export facts.

(in-package #:score-backend-midi/tests)

(defparameter +satb-voices+ '("v-8" "v-s" "v-13" "v-1e"))

(deftest rehearsal-mix-shape
  (ok (equal '(("v-8" :velocity 0 :volume 80 :pan 16)
               ("v-s" :velocity 20 :volume 127 :pan 64)
               ("v-13" :velocity 0 :volume 80 :pan 16)
               ("v-1e" :velocity 0 :volume 80 :pan 16))
             (rehearsal-mix (fixture-score "sc0-satb") "v-s")))
  (ok (equal '(("v-8" :velocity 12 :volume 110 :pan 64)
               ("v-s" :velocity 0 :volume 60 :pan 100)
               ("v-13" :velocity 0 :volume 60 :pan 100)
               ("v-1e" :velocity 0 :volume 60 :pan 100))
             (rehearsal-mix (fixture-score "sc0-satb") "v-8" :boost 12 :volume 110
                                                             :others-volume 60 :others-pan 100)))
  (ok (equal '(("v-9" :velocity 20 :volume 127 :pan 64))
             (rehearsal-mix (fixture-score "sc0-pickup") "v-9"))
      "a single voice"))

(deftest-parametrize rehearsal-mix-argument-errors
    ((label thunk)
     ("boost" (lambda () (rehearsal-mix (fixture-score "sc0-satb") "v-s" :boost 128)))
     ("negative boost" (lambda () (rehearsal-mix (fixture-score "sc0-satb") "v-s" :boost -1)))
     ("volume" (lambda () (rehearsal-mix (fixture-score "sc0-satb") "v-s" :volume 200)))
     ("others volume" (lambda () (rehearsal-mix (fixture-score "sc0-satb") "v-s" :others-volume -3)))
     ("others pan" (lambda () (rehearsal-mix (fixture-score "sc0-satb") "v-s" :others-pan 128))))
  (ok (signals-type thunk 'type-error) label))

(deftest rehearsal-mix-unknown-voice
  (let ((c (signalled (lambda () (rehearsal-mix (fixture-score "sc0-satb") "p-5")))))
    (ok (typep c 'sp:unknown-element) "a part id is not a voice id")
    (ok (equal "p-5" (and c (sp:unknown-element-id c)))))
  (ok (equal (rehearsal-mix (fixture-score "sc0-satb") "v-13")
             (handler-bind ((sp:unknown-element (lambda (c) (use-value "v-13" c))))
               (rehearsal-mix (fixture-score "sc0-satb") "tenor")))
      "USE-VALUE names the voice instead"))

(deftest rehearsal-set-is-one-mix-per-voice
  (let* ((score (fixture-score "sc0-satb"))
         (set (quietly (rehearsal-set score))))
    (ok (equal +satb-voices+ (mapcar #'car set)))
    (ok (every (lambda (entry)
                 (equalp (smf-octets (cdr entry))
                         (smf-octets (export-quietly score :mix (rehearsal-mix score (car entry))))))
               set))))

(deftest rehearsal-set-brings-each-voice-forward
  (let* ((score (fixture-score "sc0-satb"))
         (set (quietly (rehearsal-set score)))
         (base (mapcar (lambda (row) (mapcar #'fourth (sixth row))) (facts-voices "sc0-satb")))
         (bad '()))
    (loop for (focus . smf) in set
          for k from 0
          do (loop for track in (rest (mp:smf-tracks smf))
                   for j from 0
                   for velocities in base
                   for focused = (= j k)
                   do (unless (equal (list (list :program j 52)
                                           (list 7 j (if focused 127 80))
                                           (list 10 j (if focused 64 16)))
                                     (tick0-channel-events track))
                        (push (list focus j :setup) bad))
                      (unless (equal (mapcar (lambda (v) (min 127 (+ v (if focused 20 0)))) velocities)
                                     (mapcar #'fourth (track-notes track)))
                        (push (list focus j :velocity) bad))))
    (ok (null bad) (report bad))))

(deftest rehearsal-set-options
  (let* ((score (fixture-score "sc0-satb"))
         (set (quietly (rehearsal-set score :voices '("v-1e" "v-8") :division 96 :boost 30
                                            :others-pan 110 :mix '(("v-8" :volume 1))))))
    (ok (equal '("v-1e" "v-8") (mapcar #'car set)))
    (ok (every (lambda (entry) (= 96 (mp:smf-division (cdr entry)))) set) ":DIVISION passes through")
    (ok (equalp (smf-octets (cdr (first set)))
                (smf-octets (export-quietly score :division 96
                                                  :mix (rehearsal-mix score "v-1e" :boost 30
                                                                                   :others-pan 110))))
        ":MIX in KEYS is ignored")))

(deftest rehearsal-set-warns-per-file
  (ok (equal '("ids" "ids" "ids" "ids")
             (losses-of (lambda () (rehearsal-set (fixture-score "sc0-satb")))))))
