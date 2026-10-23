(define-library (control protocol)
  (export
   Choice
   choose
   choose-twice)
  (import
   (lofi base))
  (begin

    (effect Choice
      ((choose ctl (-> I64))))

    (: choose-twice (-> I64 ! Choice))
    (define (choose-twice)
      (+ (choose) (choose)))))
