(define-library (tests ui hud)
  (export answer)
  (import
   (scheme base)
   (application reducer)
   (ui core)
   (siegework model)
   (siegework hud)
   (only (lofi core) ann -> I32))
  (begin
    (application controls (state I32 1) 0
                 (choose (state (value I32)) (no-effects value))
                 (click (state) (no-effects state)))
    (define (actions)
      (hud-actions choose choose choose (click) (click) (click) (click)
                   (click) (click) (click) (click)))
    (define answer
      (ann (lambda ()
             (rect-width (placement-rect
                          (layout-ui 1280 800 (colony-hud (initial-world)
                                                          (hud-context 12 20 #f 1280 800) (actions))))))
           (-> I32)))))
