(import
 (snail core base))

(effect Pause
  ((ctl pause (dyn (Fn -> Unit)))))

;; A locally handled operation still captures the borrowed frame. Checking
;; only this function's final, empty effect row would miss it.
(: paused (All (T) (impl (Fn (Borrow T) -> Unit))))
(define (paused value)
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (pause)))
