
;; ---- Complete assembly and object-word oracle ----

(define audit-words '())
(define original-ofile-word ofile-word)
(set! ofile-word
  (lambda (value)
    (set! audit-words (cons (mod value 65536) audit-words))
    (original-ofile-word value)))
(let* ((count (read)) (expression (read)) (target (read)) (option (read)))
  (ce expression target option)
  (write (list (asm-output-get) (reverse audit-words)))
  (newline))
