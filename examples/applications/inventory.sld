;; An immutable purchase keeps the old stock available to readers.
(define-library (examples inventory)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (application reducer)
   (only (lofi core) ann -> I32))
  (begin

    ;; ---- Stock and purchase rules ----

    (define-immutable-record Stock stock
      (ore I32 stock-ore stock-ore-set))
    (application inventory (state Stock 1) (stock 50)
                 (buy (state (cost I32))
                      (no-effects
                       (if (and (>= cost 0) (<= cost (stock-ore state)))
                           (stock-ore-set state (- (stock-ore state) cost))
                           state))))

    ;; ---- Runnable checkpoint ----

    (define answer
      (ann (lambda ()
             (let* ((before ((application-initial inventory)))
                    (after (transition-state (dispatch inventory before (buy 8))))
                    (refused (transition-state (dispatch inventory after (buy 100))))
                    (negative (transition-state (dispatch inventory after (buy -1)))))
               (if (and (= (stock-ore before) 50)
                        (= (stock-ore refused) 42)
                        (= (stock-ore negative) 42))
                   (stock-ore after) 0)))
           (-> I32)))))
