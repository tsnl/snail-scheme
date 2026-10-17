;; Pure handler tests need neither a running browser nor host state storage.
(define-library (examples application-testing)
  (export answer)
  (import (scheme base) (scheme immutable) (application reducer)
          (only (lofi core) ann -> I32))
  (begin
    (define-immutable-record Stock stock
      (ore I32 stock-ore with-stock-ore))
    (application inventory (state Stock 1) (stock 10)
                 (deposit (state (amount I32))
                          (no-effects (with-stock-ore state (+ (stock-ore state) amount)))))
    (define inventory-target (destination match-owner inventory))
    (application controls (state I32 1) 0
                 (confirm (state (amount I32))
                          (transition (+ state 1) (list (enqueue inventory-target (deposit amount))))))

    ;; ---- Tests ----

    (define answer
      (ann (lambda ()
             (let* ((before ((application-initial inventory)))
                    (after (transition-state (dispatch inventory before (deposit 5))))
                    (sent (dispatch controls 0 (confirm 7)))
                    (effect (car (transition-effects sent))))
               (if (and (= (stock-ore before) 10) (= (stock-ore after) 15)
                        (= (transition-state sent) 1) (effect-send? effect)
                        (not (effect-notice? effect)) (= (effect-owner effect) match-owner)
                        (= (effect-a effect) 7) (effect-notice? (notice "Ready")))
                   42 0)))
           (-> I32)))))
