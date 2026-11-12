(import
 (snail core base)
 (snail core io))

(struct Holder
  ((items (Vector String))))

(struct Number
  ((value I64)))

;; The holder's array must survive through the frame's scanned payload after
;; its construction temporaries are cleared. Run with SNAIL_GC_STRESS=1 too.
(: local-payload (impl (Fn I64 -> String)))
(define (local-payload seed)
  (let ((held (Holder (vector-generate 8 (lambda (index) (show (+ seed index)))))))
    (let ((noise (vector-generate 50 (lambda (index) (show index)))))
      (string-append (vector-ref (::items held) 3) ":" (show (vector-length noise))))))

;; Both sides of the join produce frame candidates; aliases share the same
;; object. A returned closure instead promotes its captured number transitively.
(: joined (impl (Fn Bool -> I64)))
(define (joined first?)
  (let* ((number (if first? (Number 17) (Number 23))) (alias number))
    (::value alias)))

(: captured (impl (Fn I64 -> (dyn (Fn I64 -> I64)))))
(define (captured value)
  (let ((held (Number value))) (lambda (extra) (+ (::value held) extra))))

(: returned (impl (Fn I64 -> Number)))
(define (returned value) (Number value))

(: tail (impl (Fn Number I64 -> I64)))
(define (tail held remaining)
  (if (= remaining 0) (::value held)
      (tail (Number (+ (::value held) 1)) (- remaining 1))))

(write-line (local-payload 10))
(write-line (show (joined #t)))
(write-line (show (joined #f)))
(write-line (show ((captured 31) 11)))
(write-line (show (::value (returned 47))))
(write-line (show (tail (Number 0) 200)))
