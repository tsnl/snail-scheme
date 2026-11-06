(import
 (snail core base))

(effect Pause
  ((ctl pause (-> Unit))))

;; A locally handled operation still captures the borrowed frame. Checking
;; only this function's final, empty effect row would miss it.
(: paused (All (T) (-> (Borrow T) Unit)))
(define (paused value)
  (handle Pause
      ((pause (lambda (resume) (resume (unit)))))
    (pause)))
