(import
 (lofi base)
 (lofi io)
 (lofi text))

;; Files through the host, then through a handler that keeps them in memory.
(define path "build/tests/files-test.txt")
(write-file path "first line\nsecond λ line\n")
(display (file-exists? path))
(newline)
(write-string (read-file path))
(write-line (string-foldcase "Straße ΣΑΣ"))

(define store (ref ""))
(write-line
 (handle fs
     ((path-begin (lambda () (unit)))
      (path-character (lambda (char) (unit)))
      (path-exists (lambda () 1))
      (open-input (lambda () 7))
      (open-output (lambda () 8))
      (port-read (lambda (port) (let ((text (ref-get store)))
                                  (if (= (string-length text) 0)
                                      -1
                                      (begin (ref-set! store (substring text 1 (string-length text)))
                                             (char->i32 (string-ref text 0)))))))
      (port-write (lambda (port text) (ref-set! store (string-append (ref-get store) text))))
      (port-close (lambda (port) (unit))))
   (write-file "anywhere" "kept in memory")
   (read-file "anywhere")))
