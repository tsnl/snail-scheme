(import
 (snail core base))

;; Identical source and allocation choices for both backends. Each entry does
;; a whole batch in Wasm, keeping host-call overhead outside the inner loop.
(struct Box
  ((value I64)))

(: arithmetic (impl (Fn I64 -> I64)))
(define (arithmetic count)
  (let loop ((left count) (value 17))
    (if (= left 0) value
        (loop (- left 1) (i64-xor (+ (* value 3) 7) (i64-shift-right/logical value 5))))))

(: read-box (impl (Fn Box I64 -> I64)))
(define (read-box box value)
  (i64-xor (+ value (::value box)) (i64-shift-right/logical value 7)))

(: rooted-calls (impl (Fn I64 -> I64)))
(define (rooted-calls count)
  (let ((box (Box 31)))
    (let loop ((left count) (value 17))
      (if (= left 0) value (loop (- left 1) (read-box box value))))))

(: lists (impl (Fn I64 -> I64)))
(define (lists count)
  (fold-left + 0 (iota count)))

(: arrays (impl (Fn I64 -> I64)))
(define (arrays count)
  (vector-fold +
               0
               (vector-map (lambda (value) (+ value 3))
                           (vector-generate count (lambda (index) index)))))

(: closures (impl (Fn I64 -> I64)))
(define (closures count)
  (let ((functions (vector-generate count
                                    (lambda (index)
                                      (ann (lambda (value) (+ index value))
                                           (dyn (Fn I64 -> I64)))))))
    (vector-fold (lambda (total function) (+ total (function 3))) 0 functions)))

(effect step
  ((ctl advance (dyn (Fn I64 -> I64)))))

(: effect-loop (impl (Fn I64 -> I64 ! step)))
(define (effect-loop count)
  (let loop ((left count) (value 0))
    (if (= left 0) value (loop (- left 1) (+ value (advance left))))))

(: effects (impl (Fn I64 -> I64)))
(define (effects count)
  (handle step ((advance (lambda (value resume) (resume value))))
    (effect-loop count)))

(expose arithmetic "arithmetic")
(expose rooted-calls "rooted-calls")
(expose lists "lists")
(expose arrays "arrays")
(expose closures "closures")
(expose effects "effects")
