(import
 (snail core base)
 (snail core io))

;; Directories, renames, status and links through the runtime, in a scratch
;; directory of this program's own whose name is not all ASCII. Each line
;; is an operation and what it answered, failures included.
(define (root) (→ String) "build/tests/directories-λ")

(define (at (name String)) (→ String)
  (string-append (root) "/" name))

(define (answer (describe (Fn T → String)) (result (Result T FileError))) (→ String) (∀ (T))
  (match result
    ((Ok value)
     (let ((text (describe value))) (if (string=? text "") "ok" (string-append "ok " text))))
    ((Err error) (string-append "error: " (show error)))))

(define (done (value Unit)) (→ String)
  "")

(define (report (out OutputPort) (label String) (text String)) (→ Unit) (! mut)
  (write-line out (string-append label " -> " text)))

(define (kind-name (kind FileKind)) (→ String)
  (match kind
    ((RegularFile) "file")
    ((Directory) "directory")
    ((SymbolicLink) "link")
    ((OtherKind) "other")))

(define (status-text (status FileStatus)) (→ String)
  (match (● status kind)
    ((Directory) "directory")
    (kind (string-append (kind-name kind) " of " (show (● status size)) " bytes, modified "
                         (if (> (● status modified) 0) "after" "before") " 1970"))))

(define (names (entries (List String))) (→ String)
  (string-append "(" (string-join entries " ") ")"))

(define (main (fs Fs) (clock Clock) (out OutputPort)) (→ Unit) (! mut)
  ;; A run removes what an earlier one may have left.
  (remove-tree fs (root))
  ;; ---- Making directories ----

  (report out "make root with its parents" (answer done (make-directories fs (root))))
  (report out "make root again" (answer done (make-directory fs (root))))
  (report out "make without a parent" (answer done (make-directory fs (at "a/b"))))
  (report out "make with parents" (answer done (make-directories fs (at "a/b/c"))))
  (report out "make with parents again" (answer done (make-directories fs (at "a/b"))))
  (report out "make with parents and a trailing slash" (answer done (make-directories fs (at "a/b/s/t/"))))
  (report out "make with parents and a doubled slash"
          (answer done (make-directories fs (at "a/b/g/m//n"))))
  (write-file fs (at "a/four.txt") "four")
  (report out "make with parents over a file" (answer done (make-directories fs (at "a/four.txt"))))
  ;; ---- Listing and status ----

  (report out "list root" (answer names (list-directory fs (root))))
  (write-file fs (at "a/B.txt") "B")
  (report out "list a" (answer names (list-directory fs (at "a"))))
  (report out "list a missing directory" (answer names (list-directory fs (at "missing"))))
  (report out "list a file" (answer names (list-directory fs (at "a/four.txt"))))
  (report out "status of a file" (answer status-text (file-status fs (at "a/four.txt"))))
  (report out "status of a directory" (answer status-text (file-status fs (at "a"))))
  (report out "status of a missing path" (answer status-text (file-status fs (at "missing"))))
  ;; ---- Renaming ----

  (report out "rename" (answer done (rename-file fs (at "a/four.txt") (at "a/renamed.txt"))))
  (report out "old name exists" (show (file-exists? fs (at "a/four.txt"))))
  (report out "new name reads" (read-file fs (at "a/renamed.txt")))
  (report out "rename over an existing file"
          (answer done (rename-file fs (at "a/renamed.txt") (at "a/B.txt"))))
  (report out "replaced file reads" (read-file fs (at "a/B.txt")))
  (report out "rename a missing path" (answer done (rename-file fs (at "missing") (at "a/elsewhere"))))
  (make-directory fs (at "full"))
  (write-file fs (at "full/inside") "")
  (report out "rename over a full directory" (answer done (rename-file fs (at "a/b") (at "full"))))
  (report out "rename a file over a directory" (answer done (rename-file fs (at "a/B.txt") (at "full"))))
  ;; ---- Removing ----

  (report out "remove a full directory" (answer done (remove-directory fs (at "full"))))
  (report out "remove a directory as a file" (answer done (remove-file fs (at "full"))))
  (report out "remove a missing file" (answer done (remove-file fs (at "missing"))))
  (report out "remove a file" (answer done (remove-file fs (at "full/inside"))))
  (report out "remove the emptied directory" (answer done (remove-directory fs (at "full"))))
  ;; ---- Symbolic links ----

  (report out "link" (answer done (make-symbolic-link fs "a/B.txt" (at "link"))))
  (report out "link again" (answer done (make-symbolic-link fs "a/B.txt" (at "link"))))
  (report out "status of the link" (answer status-text (file-status fs (at "link"))))
  (report out "read the link" (answer (lambda (target) target) (read-symbolic-link fs (at "link"))))
  (report out "read through the link" (read-file fs (at "link")))
  (report out "followed status of the link" (answer status-text (followed-status fs (at "link"))))
  (report out "link to nothing" (answer done (make-symbolic-link fs "missing" (at "dangling"))))
  (report out "status of the link to nothing" (answer status-text (file-status fs (at "dangling"))))
  (report out "followed status of the link to nothing"
          (answer status-text (followed-status fs (at "dangling"))))
  (report out "remove the link to nothing" (answer done (remove-file fs (at "dangling"))))
  (report out "read a file as a link"
          (answer (lambda (target) target) (read-symbolic-link fs (at "a/B.txt"))))
  (report out "remove the link" (answer done (remove-file fs (at "link"))))
  (report out "its target remains" (show (file-exists? fs (at "a/B.txt"))))
  ;; ---- Hard links ----

  (report out "another name" (answer done (make-hard-link fs (at "a/B.txt") (at "a/also.txt"))))
  (report out "the name again" (answer done (make-hard-link fs (at "a/B.txt") (at "a/also.txt"))))
  (report out "status of the name" (answer status-text (file-status fs (at "a/also.txt"))))
  (report out "a name for nothing" (answer done (make-hard-link fs (at "missing") (at "a/none.txt"))))
  (report out "remove the first name" (answer done (remove-file fs (at "a/B.txt"))))
  (report out "the other still reads" (read-file fs (at "a/also.txt")))
  (report out "rename it back" (answer done (rename-file fs (at "a/also.txt") (at "a/B.txt"))))
  ;; ---- Removing a tree ----

  (make-symbolic-link fs "a" (at "a/b/c/up"))
  (report out "list root before" (answer names (list-directory fs (root))))
  (report out "remove the tree" (answer done (remove-tree fs (root))))
  (report out "root exists" (show (file-exists? fs (root))))
  (report out "remove the tree again" (answer done (remove-tree fs (root))))
  ;; ---- Clock ----

  (let* ((first (monotonic-nanoseconds clock)) (second (monotonic-nanoseconds clock)))
    (report out "clock never runs back" (show (>= second first))))
  (report out "a clock of the program's own"
          (show (monotonic-nanoseconds (new Clock (monotonic-nanoseconds (lambda () 42))))))
  (unit))
