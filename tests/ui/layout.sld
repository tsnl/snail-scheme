(define-library (tests ui layout)
  (export answer)
  (import
   (scheme base)
   (scheme immutable)
   (ui core)
   (only (lofi core) ann -> I32))
  (begin
    (define (example width)
      (layout-ui width 100
                 (ann (ui-row "root" (grow 1) (grow 1) 5
                              (list (ui-label "fixed" (px 30) (grow 1) "Fixed" 0)
                                    (ui-label "one" (grow 1) (grow 1) "One" 0)
                                    (ui-label "two" (grow 2) (grow 1) "Two" 0))) (Ui I32))))
    (define answer
      (ann (lambda ()
             (let* ((children (placement-children (example 100)))
                    (fixed (placement-rect (car children)))
                    (one (placement-rect (car (cdr children))))
                    (two (placement-rect (car (cdr (cdr children)))))
                    (small (placement-children (example 20))))
               (if (and (= (rect-width fixed) 30) (= (rect-x one) 35)
                        (= (rect-width one) 20) (= (rect-x two) 60) (= (rect-width two) 40)
                        (= (rect-width (placement-rect (car (cdr small)))) 0)) 1 0)))
           (-> I32)))))
