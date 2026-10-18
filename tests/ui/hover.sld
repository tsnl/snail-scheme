(define-library (tests ui hover)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (application reducer)
   (ui core)
   (ui browser)
   (only (lofi core) ann -> I32))
  (begin
    (application controls (state I32 1) 0
                 (choose (state) (no-effects state))
                 (preview (state (kind I32)) (no-effects kind)))
    (define answer
      (ann (lambda ()
             (present-ui! (destination client-owner controls)
                          (ui-layer "root" (grow 1) (grow 1)
                                    (list (ui-at 12 24
                                                 (ui-hover (preview 3) (preview 0)
                                                           (ui-button "choice" (px 120) (px 44)
                                                                      "Tower" "Preview" #t #f (choose))))
                                          (ui-at 150 24 (ui-dial "status" (px 72) (px 72)
                                                                 "42" "Ore 42; hub health" 75 100 2)))))
             1)
           (-> I32)))))
