(import
 (snail-core base)
 (snail-core io))

;; A hundred thousand yields from a tail-recursive loop, each resumed by
;; an implementation that calls `resume` in tail position. Neither the
;; loop nor the handling grows the stack: each yield returns out of the
;; loop to the handler, whose implementation is a tail call, as is its
;; call to `resume`, and the resumed loop runs from its frame until the
;; next yield returns again.
;; ANCHOR: count-down
(effect Tick
  ((ctl tick (-> I64 I64))))

(: count-down (-> I64 I64 I64 ! Tick))
(define (count-down n total)
  (if (= n 0)
      total
      (count-down (- n 1) (+ total (tick n)))))

(display (handle Tick ((tick (lambda (n resume) (resume (* n 2)))))
           (count-down 100000 0)))
(newline)
;; ANCHOR_END: count-down

;; The same loop with a yield only every thousandth step, which runs as an
;; ordinary loop in between.
(: sparse (-> I64 I64 I64 ! Tick))
(define (sparse n total)
  (cond ((= n 0) total)
        ((= (remainder n 1000) 0) (sparse (- n 1) (+ total (tick n))))
        (else (sparse (- n 1) (+ total 1)))))

(display (handle Tick ((tick (lambda (n resume) (resume 0))))
           (sparse 1000000 0)))
(newline)
