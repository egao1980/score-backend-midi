;;;; SC4 fixture: rhythms in 4/4, D major, for tick arithmetic and the exact
;;;; import: dotted values, sixteenths, a double-dotted quarter, thirty-seconds,
;;;; triplet eighths, a triplet quarter and eighth, sextuplet sixteenths, and a
;;;; dotted half tied across the barline. Hand-built, MIT.
(:score
 :metadata (:title "Rhythms")
 :id-counter 38
 :measures
 ((:measure :id "m-1" :time "4/4" :key "D major" :tempo ((:tempo-mark :id "tm-2" :bpm 80 :beat-unit 1/4)))
  (:measure :id "m-3")
  (:measure :id "m-4")
  (:measure :id "m-5" :barline :final))
 :parts
 ((:part :id "p-6" :name "Flute" :staves ((:staff :id "st-7"))
   :voices
   ((:voice :id "v-8"
     :measures
     (((:note :id "e-9" :pitch "D5" :duration 3/8) (:note :id "e-a" :pitch "E5" :duration 1/8)
       (:note :id "e-b" :pitch "F#5" :duration 1/16) (:note :id "e-c" :pitch "G5" :duration 1/16)
       (:note :id "e-d" :pitch "A5" :duration 1/16) (:note :id "e-e" :pitch "B5" :duration 1/16)
       (:note :id "e-f" :pitch "A5" :duration 3/16) (:note :id "e-g" :pitch "G5" :duration 1/16))
      ((:note :id "e-h" :pitch "F#5" :duration 7/16) (:note :id "e-i" :pitch "E5" :duration 1/16)
       (:note :id "e-j" :pitch "D5" :duration 1/32) (:note :id "e-k" :pitch "E5" :duration 1/32)
       (:note :id "e-l" :pitch "F#5" :duration 1/16) (:note :id "e-m" :pitch "G5" :duration 1/8)
       (:note :id "e-n" :pitch "A5" :duration 1/12 :tuplet 3/2) (:note :id "e-o" :pitch "G5" :duration 1/12 :tuplet 3/2)
       (:note :id "e-p" :pitch "F#5" :duration 1/12 :tuplet 3/2))
      ((:note :id "e-q" :pitch "E5" :duration 1/6 :tuplet 3/2) (:note :id "e-r" :pitch "D5" :duration 1/12 :tuplet 3/2)
       (:note :id "e-s" :pitch "C#5" :duration 1/24 :tuplet 3/2) (:note :id "e-t" :pitch "D5" :duration 1/24 :tuplet 3/2)
       (:note :id "e-u" :pitch "E5" :duration 1/24 :tuplet 3/2) (:note :id "e-v" :pitch "F#5" :duration 1/24 :tuplet 3/2)
       (:note :id "e-w" :pitch "G5" :duration 1/24 :tuplet 3/2) (:note :id "e-x" :pitch "A5" :duration 1/24 :tuplet 3/2)
       (:note :id "e-y" :pitch "B5" :duration 1/2 :tie (:tie :id "ti-z" :end "e-10")))
      ((:note :id "e-10" :pitch "B5" :duration 1/4) (:note :id "e-11" :pitch "A5" :duration 1/4)
       (:note :id "e-12" :pitch "D5" :duration 1/2))))))))
