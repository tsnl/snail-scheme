(import
 (snail-core base)
 (snail-core io)
 (snail-core text))

;; Files through the host, with a path whose scalars are not all ASCII.
(define path "build/tests/files-λ😀.txt")
(write-file path "first line\nsecond λ line\n")
(display (file-exists? path))
(newline)
(write-string (read-file path))
(write-line (string-foldcase "Straße ΣΑΣ"))

;; A handler receives each whole path, so it can decide by name alone, and
;; can list a directory from memory: three scalars with a NUL between two
;; names.
(write-line
 (show (handle fs
           ((path-exists (lambda (name) (if (string=? name "λ/😀 name") 1 0)))
            (open-input (lambda (name) 0))
            (open-output (lambda (name) 0))
            (port-read (lambda (port) -1))
            (port-read-byte (lambda (port) -1))
            (port-write (lambda (port text) (unit)))
            (port-write-byte (lambda (port byte) (unit)))
            (port-close (lambda (port) (unit)))
            (path-make-directory (lambda (name) -1))
            (path-rename (lambda (names) -1))
            (path-remove-file (lambda (name) -1))
            (path-remove-directory (lambda (name) -1))
            (path-list (lambda (name) (if (string=? name "λ") 3 -1)))
            (path-status (lambda (name) -1))
            (path-make-link (lambda (names) -1))
            (path-read-link (lambda (name) -1))
            (reply-character
             (lambda (index) (if (= index 1) #\null (string-ref "x😀y" (i32->i64 index)))))
            (status-size (lambda () 0))
            (status-modified (lambda () 0)))
         (and (file-exists? "λ/😀 name") (not (file-exists? "elsewhere"))
              (match (list-directory "λ")
                ((Ok names) (string=? (string-join names ",") "x,y"))
                ((Err _) #f))
              (match (list-directory "elsewhere")
                ((Ok _) #f)
                ((Err error) (string=? (show error) "no such file or directory")))))))
