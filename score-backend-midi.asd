(defsystem "score-backend-midi"
  :version "0.1.0"
  :description "Standard MIDI File export and import for score-protocol: tracks and channels per voice, tempo map, lyrics, chord text, unfolded repeats, rehearsal mixes; quantisation through sat-protocol, spelling through music-theory"
  :author "egao1980"
  :license "MIT"
  :depends-on ((:version "score-protocol" "0.2.0")
               (:version "midi-protocol" "0.1.0")
               (:version "music-theory" "0.5.0")
               (:version "sat-protocol" "0.2.0")
               "sat-backend-cdcl"
               ;; score-protocol returns FSet seqs; read through fset: directly
               "fset")
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "tables")
               (:file "export")
               (:file "mix")
               (:file "quantize")
               (:file "tracks")
               (:file "measures")
               (:file "import"))
  :in-order-to ((test-op (test-op "score-backend-midi/tests"))))

(defsystem "score-backend-midi/tests"
  :depends-on ("score-backend-midi" (:version "rove" "0.11.1") "cl-stack-pathlib"
               "process-backend-uiop")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "export-test")
               (:file "mix-test")
               (:file "quantize-test")
               (:file "import-test")
               (:file "performance-test")
               (:file "spelling-test")
               (:file "mido-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
