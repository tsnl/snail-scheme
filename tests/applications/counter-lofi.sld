(define-library (tests counter-lofi)
  (export answer)
  (import
   (lofi core)
   (lofi base)
   (application reducer))
  (begin
    ;; Declaring handlers, constructing requests and dispatching explicit state
    ;; must never force the initializer. Reusing a request must not capture state.
    (application counter (state I32 1) (unreachable)
                 (reset-count (state) (no-effects 0))
                 (add (state (amount I32)) (no-effects (i32-add state amount)))
                 (adjust (state (left I32) (right I32))
                         (no-effects (i32-sub (i32-add state left) right))))
    (def answer (-> I32)
         (lambda ()
           (begin
             (let command (add 2))
             (if (i32-eq (transition-state (dispatch counter 40 command)) 42)
                 (if (i32-eq (transition-state (dispatch counter 100 command)) 102)
                     (if (i32-eq (transition-state (dispatch counter 55 (reset-count))) 0)
                         (transition-state (dispatch counter 40 (adjust 9 7))) 0) 0) 0))))))
