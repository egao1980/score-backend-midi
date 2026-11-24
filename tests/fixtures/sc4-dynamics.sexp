;;;; SC4 fixture: point dynamics on one voice in 4/4, C major: levels, an
;;;; accent (sf) that returns to the level before it, fp and sfp that leave
;;;; piano in force, a dynamic on a rest, and rfz. Exercises the velocity
;;;; rules of src/export.lisp. Hand-built, MIT.
(:score
 :metadata (:title "Dynamics")
 :id-counter 32
 :measures
 ((:measure :id "m-1" :time "4/4" :key "C major" :tempo ((:tempo-mark :id "tm-2" :bpm 96 :beat-unit 1/4)))
  (:measure :id "m-3")
  (:measure :id "m-4")
  (:measure :id "m-5" :barline :final))
 :parts
 ((:part :id "p-6" :name "Clarinet" :staves ((:staff :id "st-7"))
   :voices
   ((:voice :id "v-8"
     :measures
     (((:note :id "e-9" :pitch "C4" :duration 1/4 :dynamic (:dynamic :id "dy-a" :value :p))
       (:note :id "e-b" :pitch "D4" :duration 1/4)
       (:note :id "e-c" :pitch "E4" :duration 1/4 :dynamic (:dynamic :id "dy-d" :value :mf))
       (:note :id "e-e" :pitch "F4" :duration 1/4 :dynamic (:dynamic :id "dy-f" :value :sf)))
      ((:note :id "e-g" :pitch "G4" :duration 1/4)
       (:note :id "e-h" :pitch "A4" :duration 1/4 :dynamic (:dynamic :id "dy-i" :value :fp))
       (:note :id "e-j" :pitch "B4" :duration 1/4)
       (:note :id "e-k" :pitch "C5" :duration 1/4 :dynamic (:dynamic :id "dy-l" :value :ff)))
      ((:note :id "e-m" :pitch "B4" :duration 1/4 :dynamic (:dynamic :id "dy-n" :value :sfz))
       (:note :id "e-o" :pitch "A4" :duration 1/4)
       (:rest :id "e-p" :duration 1/4 :dynamic (:dynamic :id "dy-q" :value :pp))
       (:note :id "e-r" :pitch "G4" :duration 1/4))
      ((:note :id "e-s" :pitch "F4" :duration 1/2 :dynamic (:dynamic :id "dy-t" :value :mp))
       (:note :id "e-u" :pitch "E4" :duration 1/4 :dynamic (:dynamic :id "dy-v" :value :sfp))
       (:note :id "e-w" :pitch "D4" :duration 1/4))))))))
