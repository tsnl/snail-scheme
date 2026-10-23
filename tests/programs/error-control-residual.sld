(import
 (lofi base))

(effect Choice
  ((choose ctl (-> I64))))

(effect Other
  ((other (-> I64))))

(: total (-> I64))
(define (total)
  (handle Choice
      ((choose (lambda (resume) (resume 1))))
    (+ (choose) (other))))

(total)
