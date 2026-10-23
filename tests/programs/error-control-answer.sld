(import
 (lofi base))

(effect Choice
  ((choose ctl (-> I64))))

(handle Choice
    ((choose (lambda (resume) "wrong")))
  (choose))
