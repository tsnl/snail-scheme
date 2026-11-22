;; Capabilities. A function writes only to the port it is given, so its
;; caller decides where the lines go.
(import
 (snail core base)
 (snail core io))

(define (total-cost (log OutputPort) (prices (List I64))) (→ I64)
  (fold-left (lambda (total price)
               (write-line log (string-append "adding " (show price)))
               (+ total price))
             0 prices))

;; A port is a record of the function that writes it, so a program makes
;; its own: this one keeps nothing.
(define (nowhere) (→ OutputPort)
  (new OutputPort (write-string (lambda (text) (unit)))))

;; The same function, quiet or verbose, depending only on the port.
(define (main (out OutputPort)) (→ Unit)
  (display out (total-cost (nowhere) (list 3 4 5)))
  (newline out)
  (display out (total-cost out (list 1 2)))
  (newline out)
  (unit))
