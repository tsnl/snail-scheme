(import
 (snail core base)
 (snail core io))

;; Whole texts through the runtime, in a scratch directory of this
;; program's own: a text written and read back, and each failure a value,
;; where read-file and write-file would fail the program. Each line is an
;; operation and what it answered.
(define (root) (→ String) "build/tests/text-files")

(define (at (name String)) (→ String)
  (string-append (root) "/" name))

(define (report (out OutputPort) (label String) (text String)) (→ Unit) (! mut)
  (write-line out (string-append label " -> " text)))

;; What a read answered, the text described by `describe`.
(define (read-report (fs Fs)
                     (out OutputPort)
                     (label String)
                     (name String)
                     (limit I64)
                     (describe (Fn String → String)))
  (→ Unit)
  (! mut)
  (report out label (match (read-text-file fs (at name) limit)
                      ((Ok text) (string-append "ok " (describe text)))
                      ((Err error) (string-append "error: " (show error))))))

(define (as-is (text String)) (→ String)
  text)

(define (characters (text String)) (→ String)
  (string-append (show (string-length text)) " characters"))

(define (write-report (fs Fs) (out OutputPort) (label String) (name String) (text String))
  (→ Unit)
  (! mut)
  (report out label (match (write-text-file fs (at name) text (CreateOrReplace))
                      ((Ok _) "ok")
                      ((Err error) (string-append "error: " (show error))))))

(define (main (fs Fs) (out OutputPort)) (→ Unit) (! mut)
  (remove-tree fs (root))
  (make-directories fs (root))
  (write-report fs out "write" "λ.txt" "one λ, two")
  (read-report fs out "read" "λ.txt" 64 as-is)
  (read-report fs out "read at its length" "λ.txt" 11 as-is)
  (read-report fs out "read past its limit" "λ.txt" 10 as-is)
  (write-report fs out "replace" "λ.txt" "short")
  (read-report fs out "read again" "λ.txt" 64 as-is)
  (write-report fs out "write a NUL" "nul.txt" (string-append "a" (make-string 1 #\null) "b"))
  (read-report fs out "read a NUL" "nul.txt" 64 characters)
  (write-bytes fs (at "latin1.txt") (list->array (list (i32->u8 233))))
  (read-report fs out "read Latin-1" "latin1.txt" 64 as-is)
  (make-symbolic-link fs "λ.txt" (at "link"))
  (read-report fs out "read a link" "link" 64 as-is)
  (read-report fs out "read a directory" "" 64 as-is)
  (read-report fs out "read nothing" "missing" 64 as-is)
  (write-report fs out "write into nothing" "missing/file" "text")
  (write-report fs
                out
                "write a path with a NUL"
                (string-append "a" (make-string 1 #\null) "b")
                "text")
  (remove-tree fs (root))
  (unit))
