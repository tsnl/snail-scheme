(import
 (lofi base)
 (lofi io))

;; Loops written with `when` run in constant stack space.
(define counter (ref 0))
(let loop ((index 0))
  (when (< index 3000000)
    (ref-set! counter (+ (ref-get counter) 1))
    (loop (+ index 1))))
(display (ref-get counter))
(newline)
(define text (make-string 200000 #\a))
(write-line (substring text 0 3))
(display (string-length (string-append text text)))
(newline)
