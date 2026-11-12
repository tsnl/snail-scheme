(import
 (snail core base))

(effect Pause
  ((ctl pause (Fn → Unit))))

;; A locally handled operation still captures the borrowed frame. Checking
;; only this function's final, empty effect row would miss it.
(define (paused (value (Borrow T))) (→ Unit) (∀ T)
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (pause)))
