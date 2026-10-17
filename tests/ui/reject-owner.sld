(define-library (tests ui reject-owner)
  (export answer)
  (import
   (scheme base)
   (application reducer)
   (ui core)
   (ui browser)
   (only (lofi core) ann -> I32))
  (begin
    (application first-app (state I32 1) 0
                 (first-click (state) (no-effects state)))
    (application second-app (state I32 1) 0
                 (second-click (state) (no-effects state)))
    (define answer
      (ann (lambda ()
             (present-ui! (destination client-owner first-app)
                          (ui-button "wrong-owner" (px 100) (px 44) "Wrong" "" #t #f (second-click)))
             1)
           (-> I32)))))
