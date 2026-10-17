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
    (define (scroll-example)
      (layout-ui 100 50
                 (ann (ui-scroll "scroll" (grow 1) (grow 1) 120 0
                                 (list (ui-label "content" (grow 1) (px 100) "Scrollable" 0))) (Ui I32))))
    (define answer
      (ann (lambda ()
             (let* ((children (placement-children (example 100)))
                    (fixed (placement-rect (car children)))
                    (one (placement-rect (car (cdr children))))
                    (two (placement-rect (car (cdr (cdr children)))))
                    (small (placement-children (example 20)))
                    (scroll (placement-rect (car (placement-children (scroll-example))))))
               (if (and (= (rect-width fixed) 30) (= (rect-x one) 35)
                        (= (rect-width one) 20) (= (rect-x two) 60) (= (rect-width two) 40)
                        (= (rect-width (placement-rect (car (cdr small)))) 0)
                        (= (rect-width scroll) 84) (= (rect-height scroll) 100)) 1 0)))
           (-> I32)))))
