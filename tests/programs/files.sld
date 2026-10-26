(import
 (lofi base)
 (lofi io)
 (lofi text))

;; Files through the host, with a path whose scalars are not all ASCII.
(define path "build/tests/files-λ😀.txt")
(write-file path "first line\nsecond λ line\n")
(display (file-exists? path))
(newline)
(write-string (read-file path))
(write-line (string-foldcase "Straße ΣΑΣ"))

;; A handler receives each whole path, so it can decide by name alone.
(write-line
 (show (handle fs
           ((path-exists (lambda (name) (if (string=? name "λ/😀 name") 1 0)))
            (open-input (lambda (name) 0))
            (open-output (lambda (name) 0))
            (port-read (lambda (port) -1))
            (port-read-byte (lambda (port) -1))
            (port-write (lambda (port text) (unit)))
            (port-write-byte (lambda (port byte) (unit)))
            (port-close (lambda (port) (unit))))
         (and (file-exists? "λ/😀 name") (not (file-exists? "elsewhere"))))))
