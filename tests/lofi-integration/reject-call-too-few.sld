(import
 (lofi base))
(def combine (-> I32 I32 I32) (lambda (left right) (+ left right)))
(combine 1)
