(import
 (snail core base)
 (snail core io)
 (snail shell text))

;; Files through the host, with a path whose scalars are not all ASCII.
(define (path) (→ String) "build/tests/files-λ😀.txt")

(define (main (fs Fs) (out OutputPort)) (→ Unit)
  (write-file fs (path) "first line\nsecond λ line\n")
  (display out (file-exists? fs (path)))
  (newline out)
  (out::write-string (read-file fs (path)))
  (write-line out (string-foldcase "Straße ΣΑΣ"))
  (unit))
