(import
 (lofi base)
 (lofi io)
 (lofi text))

;; File effects through the runtime.
(define path "build/tests/files-test.txt")
(write-file path "first line\nsecond λ line\n")
(display (file-exists? path))
(newline)
(write-string (read-file path))
(write-line (string-foldcase "Straße ΣΑΣ"))
