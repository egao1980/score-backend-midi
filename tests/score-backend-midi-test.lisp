(defpackage #:score-backend-midi/tests
  (:use #:cl #:rove))

(in-package #:score-backend-midi/tests)

(deftest skeleton-loads
  (ok (find-package '#:score-backend-midi)))
