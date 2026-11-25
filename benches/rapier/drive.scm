(import
 (snail core base))

(extern reset-track "snail.core.support" "snail:rapier/reset" (Fn → Unit))
(extern step-track "snail.core.support" "snail:rapier/step" (Fn F64 → F64))
(extern chassis-height "snail.core.support" "snail:rapier/height" (Fn → F64))
(extern grounded-wheels "snail.core.support" "snail:rapier/grounded-wheels" (Fn → I32))
(extern close-track "snail.core.support" "snail:rapier/close" (Fn → Unit))

(record Drive
  ((rest-height F64)
   (wheels I32)
   (travel F64)))

(define (advance (ticks I64) (force F64)) (→ F64)
  (let run ((left ticks) (z 0.0))
    (if (= left 0) z (run (- left 1) (step-track force)))))

(define (drive (force F64)) (→ Drive)
  (reset-track)
  (let* ((start (advance 180 0.0)) (height (chassis-height)) (wheels (grounded-wheels))
         (end (advance 120 force))
         (result (new Drive (rest-height height) (wheels wheels) (travel (- end start)))))
    (close-track)
    result))

;; Exercise both the parked and powered car through the same GC-managed shell.
(define (travel (force F64)) (→ F64)
  (let ((result (drive force)))
    (unless (and (> (● result rest-height) 0.24) (< (● result rest-height) 1.0)
                 (= (● result wheels) (i64->i32 4)))
      (panic "the falling chassis did not settle on four wheels"))
    (● result travel)))

(expose travel "travel")
