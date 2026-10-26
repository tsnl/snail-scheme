(import
 (lofi base))

(effect Choice
  ((choose ctl (-> I64))))

(handle Choice
    ((choose (lambda (resume) (string-length (resume 1)))))
  (choose))
