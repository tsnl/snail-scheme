(import
 (lofi core)
 (lofi base))

(def define-counter
     (syntax-rules ()
       ((_ State make-state state-value Next next next-i32 advance)
        (begin
          (data State ()
            (make-state
             (value I32 state-value)))
          (begin
            (typeclass Next (T)
                       (: next (-> T T)))
            (instance next-i32 (Next I32)
                      (next (lambda (value) (+ value 1)))))
          (def advance (lambda (state) (make-state (next (state-value state)))))))))
(define-counter Counter make-counter counter-value Next next next-i32 advance)
(counter-value (advance (make-counter 41)))
