(import
 (lofi base)
 (lofi io))

(typeclass (Describe T)
  (: describe (-> T String)))

(instance (Describe I64)
  (define (describe n) (string-append "int " (show n))))

(instance (Describe Bool)
  (define (describe b) (if b "true" "false")))

(instance (Describe (List T))
  (requires (Describe T))
  (define (describe items)
    (string-append "[" (string-append (string-join (map describe items) ", ") "]"))))

(instance (Describe (Option T))
  (requires (Describe T))
  (define (describe value)
    (match value
      ((None) "nothing")
      ((Some x) (string-append "just " (describe x))))))

(: describe-twice (All (T) (requires (Describe T)) (-> T String)))
(define (describe-twice value)
  (string-append (describe value) (string-append " / " (describe value))))

(: sum (All (T) (requires (Num T)) (-> (List T) T T)))
(define (sum items zero)
  (fold-left + zero items))

(write-line (describe (list 1 2 3)))
(write-line (describe (list (Some #t) (None))))
(write-line (describe-twice (list (list 1) (list))))
(display (sum (list 1 2 3) 0))
(newline)
(display (sum (list 1.5 2.5) 0.0))
(newline)
(display (max 3 9))
(newline)
(write-line (show (< "apple" "banana")))
