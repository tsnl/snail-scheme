(import
 (snail core base)
 (snail core io))

;; Whole texts through the runtime, in a scratch directory of this
;; program's own: a text written and read back, and each failure a value,
;; where read-file and write-file would fail the program. Each line is an
;; operation and what it answered.
(define root "build/tests/text-files")

(: at (-> String String))
(define (at name)
  (string-append root "/" name))

(: report (-> String String Unit ! console))
(define (report label text)
  (write-line (string-append label " -> " text)))

;; What a read answered, the text described by `describe`.
(: read-report (-> String String I64 (-> String String) Unit ! console fs))
(define (read-report label name limit describe)
  (report label (match (read-text-file (at name) limit)
                  ((Ok text) (string-append "ok " (describe text)))
                  ((Err error) (string-append "error: " (show error))))))

(: as-is (-> String String))
(define (as-is text)
  text)

(: characters (-> String String))
(define (characters text)
  (string-append (show (string-length text)) " characters"))

(: write-report (-> String String String Unit ! console fs))
(define (write-report label name text)
  (report label (match (write-text-file (at name) text)
                  ((Ok _) "ok")
                  ((Err error) (string-append "error: " (show error))))))

(remove-tree root)
(make-directories root)
(write-report "write" "λ.txt" "one λ, two")
(read-report "read" "λ.txt" 64 as-is)
(read-report "read at its length" "λ.txt" 11 as-is)
(read-report "read past its limit" "λ.txt" 10 as-is)
(write-report "replace" "λ.txt" "short")
(read-report "read again" "λ.txt" 64 as-is)
(write-report "write a NUL" "nul.txt" (string-append "a" (make-string 1 #\null) "b"))
(read-report "read a NUL" "nul.txt" 64 characters)
(write-bytes (at "latin1.txt") (list->vector (list (i32->u8 233))))
(read-report "read Latin-1" "latin1.txt" 64 as-is)
(make-symbolic-link "λ.txt" (at "link"))
(read-report "read a link" "link" 64 as-is)
(read-report "read a directory" "" 64 as-is)
(read-report "read nothing" "missing" 64 as-is)
(write-report "write into nothing" "missing/file" "text")
(write-report "write a path with a NUL" (string-append "a" (make-string 1 #\null) "b") "text")
(remove-tree root)
