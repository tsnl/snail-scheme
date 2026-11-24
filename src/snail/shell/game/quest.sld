;; A quest is a typed state transition over the observations of one tick.
;; Rules match the stage at the start of the tick. The first observation
;; with a matching rule advances it once. Only the stage belongs in a save.
(define-library (snail shell game quest)
  (export define-quest)
  (import
   (snail core base))
  (begin
    (define-syntax define-quest
      (syntax-rules ()
        ((_ (name Stage Event) (from on result) ...)
         (define (name (stage Stage) (observations (List Event))) (→ Stage)
           (let scan ((rest observations))
             (match rest
               ((Nil) stage)
               ((Cons event later)
                (match (new Pair (first stage) (second event))
                  ((Pair from on) result) ...
                  (_ (scan later))))))))))))
