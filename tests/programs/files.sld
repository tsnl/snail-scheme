(import
 (lofi base)
 (lofi io)
 (lofi text))

;; Files through the host, then through a handler that keeps them in memory.
(define path "build/tests/files-λ😀.txt")
(write-file path "first line\nsecond λ line\n")
(display (file-exists? path))
(newline)
(write-string (read-file path))
(write-line (string-foldcase "Straße ΣΑΣ"))

(define store (ref ""))
(write-line
 (handle fs
     ((path-exists (lambda (path) (if (string=? path "anywhere") 1 0)))
      (open-input (lambda (path) (if (string=? path "anywhere") 7 (panic "wrong input path"))))
      (open-output (lambda (path) (if (string=? path "anywhere") 8 (panic "wrong output path"))))
      (port-read (lambda (port) (let ((text (ref-get store)))
                                  (if (= (string-length text) 0)
                                      -1
                                      (begin (ref-set! store (substring text 1 (string-length text)))
                                             (char->i32 (string-ref text 0)))))))
      (port-read-byte (lambda (port) -1))
      (port-write (lambda (port text) (ref-set! store (string-append (ref-get store) text))))
      (port-write-byte (lambda (port byte) (unit)))
      (port-close (lambda (port) (unit))))
   (write-file "anywhere" "kept in memory")
   (read-file "anywhere")))
