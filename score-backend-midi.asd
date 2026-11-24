(defsystem "score-backend-midi"
  :version "0.0.1"
  :description "Standard MIDI File export and import for score-protocol: tracks, tempo map, lyrics, quantisation, spelling"
  :author "egao1980"
  :license "MIT"
  :pathname "src"
  :serial t
  :components ((:file "package"))
  :in-order-to ((test-op (test-op "score-backend-midi/tests"))))

(defsystem "score-backend-midi/tests"
  :depends-on ("score-backend-midi" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "score-backend-midi-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
