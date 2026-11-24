;;;; SC4 fixture: a strophic hymn line in 3/4, F major: bars 1-3 repeated,
;;;; the third bar a first ending and the fourth a second ending, with verse 1
;;;; and verse 2 under the notes, for :VERSE :PASS. Text after Isaac Watts
;;;; ("Joy to the World", 1719, public domain). Hand-built, MIT.
(:score
 :metadata (:title "Strophic Line" :lyricist "Isaac Watts")
 :id-counter 31
 :measures
 ((:measure :id "m-1" :time "3/4" :key "F major" :repeat-start t
   :tempo ((:tempo-mark :id "tm-2" :bpm 90 :beat-unit 1/4)))
  (:measure :id "m-3")
  (:measure :id "m-4" :repeat-end 2 :ending (:ending :id "en-5" :passes (1)))
  (:measure :id "m-6" :barline :final :ending (:ending :id "en-7" :passes (2))))
 :parts
 ((:part :id "p-8" :name "Voice" :staves ((:staff :id "st-9"))
   :voices
   ((:voice :id "v-a"
     :measures
     (((:note :id "e-b" :pitch "F4" :duration 1/2 :lyrics ((:lyric :id "ly-c" :text "Joy") (:lyric :id "ly-d" :verse 2 :text "Let")))
       (:note :id "e-e" :pitch "G4" :duration 1/4 :lyrics ((:lyric :id "ly-f" :text "to") (:lyric :id "ly-g" :verse 2 :text "ev" :syllabic :begin))))
      ((:note :id "e-h" :pitch "A4" :duration 1/4 :lyrics ((:lyric :id "ly-i" :text "the") (:lyric :id "ly-j" :verse 2 :text "ery" :syllabic :end)))
       (:note :id "e-k" :pitch "Bb4" :duration 1/4 :lyrics ((:lyric :id "ly-l" :text "world") (:lyric :id "ly-m" :verse 2 :text "heart")))
       (:note :id "e-n" :pitch "C5" :duration 1/4 :lyrics ((:lyric :id "ly-o" :text "the") (:lyric :id "ly-p" :verse 2 :text "pre" :syllabic :begin))))
      ((:note :id "e-q" :pitch "A4" :duration 3/4 :lyrics ((:lyric :id "ly-r" :text "Lord") (:lyric :id "ly-s" :verse 2 :text "pare" :syllabic :end))))
      ((:note :id "e-t" :pitch "F4" :duration 3/4 :fermata (:fermata :id "fe-u") :lyrics ((:lyric :id "ly-v" :verse 2 :text "room"))))))))))
