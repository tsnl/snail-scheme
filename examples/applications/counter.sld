;; Run with the map compiler or scripts/build-lofi --export answer. No browser
;; or state service is needed to exercise a pure application transition.
(define-library (examples counter)
  (export answer)
  (import
   (scheme base)
   (application reducer)
   (only (lofi core) ann -> I32))
  (begin
    (application counter (state I32 1) 0
                 (add (state (amount I32)) (no-effects (+ state amount)))
                 (reset (state) (no-effects 0)))
    (define answer
      (ann (lambda () (transition-state (dispatch counter 40 (add 2)))) (-> I32)))))
