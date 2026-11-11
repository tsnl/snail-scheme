(import
 (snail core base)
 (snail core io))

(struct Counter
  ((value (Ref I64))))
(instance (Drop (! mut console) Counter)
  (define (drop counter)
    (match counter
      ((Counter value) (write-line (string-append "released " (show (ref-get value))))))))

(let* ((counter (Counter (ref 0)))
       (advance (ann (lambda (amount)
                       (set! (ref-get (::value counter)) (+ (ref-get (::value counter)) amount))
                       (ref-get (::value counter)))
                     (impl (FnMut I64 -> I64 ! mut console)))))
  (write-line (show (advance 3)))
  (write-line (show (advance 4)))
  (drop advance))

;; An exclusive callable can reborrow its owned exclusive callback.
(let* ((counter (Counter (ref 0)))
       (inner (ann (lambda (amount)
                     (set! (ref-get (::value counter)) (+ (ref-get (::value counter)) amount))
                     (ref-get (::value counter)))
                   (impl (FnMut I64 -> I64 ! mut console))))
       (outer (ann (lambda (amount) (inner amount))
                   (impl (FnMut I64 -> I64 ! mut console)))))
  (write-line (show (outer 2)))
  (drop outer))

(: consume
   (All (F)
        (requires (FnOnce F I64 -> I64 ! mut console))
        (impl (Fn F I64 -> I64 ! mut console))))
(define (consume function value)
  (function value))

;; Consuming an exclusive implementation runs its capture cleanup once.
(let* ((counter (Counter (ref 0)))
       (advance (ann (lambda (amount)
                       (set! (ref-get (::value counter)) amount)
                       (ref-get (::value counter)))
                     (impl (FnMut I64 -> I64 ! mut console)))))
  (write-line (show (consume advance 9))))

(struct Work
  ((run (dyn (FnMut I64 -> I64 ! mut console)))))

;; An erased exclusive receiver can be called through its owner's field.
(let* ((counter (Counter (ref 0)))
       (work (Work (lambda (amount)
                     (set! (ref-get (::value counter)) amount)
                     (ref-get (::value counter))))))
  (write-line (show ((::run work) 12)))
  (drop work))
