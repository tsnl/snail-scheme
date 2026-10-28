(import
 (snail-core base)
 (snail-core io))

;; Directories, renames, status and links through the runtime, in a scratch
;; directory of this program's own whose name is not all ASCII. Each line
;; is an operation and what it answered, failures included.
(define root "build/tests/directories-λ")

(: at (-> String String))
(define (at name)
  (string-append root "/" name))

(: answer (All (T) (-> (-> T String) (Result T FileError) String)))
(define (answer describe result)
  (match result
    ((Ok value) (let ((text (describe value))) (if (string=? text "") "ok" (string-append "ok " text))))
    ((Err error) (string-append "error: " (show error)))))

(: done (-> Unit String))
(define (done value)
  "")

(: report (-> String String Unit ! console))
(define (report label text)
  (write-line (string-append label " -> " text)))

(: kind-name (-> FileKind String))
(define (kind-name kind)
  (match kind
    ((RegularFile) "file")
    ((Directory) "directory")
    ((SymbolicLink) "link")
    ((OtherKind) "other")))

(: status-text (-> FileStatus String))
(define (status-text status)
  (match (FileStatus-kind status)
    ((Directory) "directory")
    (kind (string-append (kind-name kind) " of " (show (FileStatus-size status)) " bytes, modified "
                         (if (> (FileStatus-modified status) 0) "after" "before") " 1970"))))

(: names (-> (List String) String))
(define (names entries)
  (string-append "(" (string-join entries " ") ")"))

;; A run removes what an earlier one may have left.
(remove-tree root)

;; ---- Making directories ----

(report "make root with its parents" (answer done (make-directories root)))
(report "make root again" (answer done (make-directory root)))
(report "make without a parent" (answer done (make-directory (at "a/b"))))
(report "make with parents" (answer done (make-directories (at "a/b/c"))))
(report "make with parents again" (answer done (make-directories (at "a/b"))))
(write-file (at "a/four.txt") "four")
(report "make with parents over a file" (answer done (make-directories (at "a/four.txt"))))

;; ---- Listing and status ----

(report "list root" (answer names (list-directory root)))
(write-file (at "a/B.txt") "B")
(report "list a" (answer names (list-directory (at "a"))))
(report "list a missing directory" (answer names (list-directory (at "missing"))))
(report "list a file" (answer names (list-directory (at "a/four.txt"))))
(report "status of a file" (answer status-text (file-status (at "a/four.txt"))))
(report "status of a directory" (answer status-text (file-status (at "a"))))
(report "status of a missing path" (answer status-text (file-status (at "missing"))))

;; ---- Renaming ----

(report "rename" (answer done (rename-file (at "a/four.txt") (at "a/renamed.txt"))))
(report "old name exists" (show (file-exists? (at "a/four.txt"))))
(report "new name reads" (read-file (at "a/renamed.txt")))
(report "rename over an existing file" (answer done (rename-file (at "a/renamed.txt") (at "a/B.txt"))))
(report "replaced file reads" (read-file (at "a/B.txt")))
(report "rename a missing path" (answer done (rename-file (at "missing") (at "a/elsewhere"))))
(make-directory (at "full"))
(write-file (at "full/inside") "")
(report "rename over a full directory" (answer done (rename-file (at "a/b") (at "full"))))
(report "rename a file over a directory" (answer done (rename-file (at "a/B.txt") (at "full"))))

;; ---- Removing ----

(report "remove a full directory" (answer done (remove-directory (at "full"))))
(report "remove a directory as a file" (answer done (remove-file (at "full"))))
(report "remove a missing file" (answer done (remove-file (at "missing"))))
(report "remove a file" (answer done (remove-file (at "full/inside"))))
(report "remove the emptied directory" (answer done (remove-directory (at "full"))))

;; ---- Symbolic links ----

(report "link" (answer done (make-symbolic-link "a/B.txt" (at "link"))))
(report "link again" (answer done (make-symbolic-link "a/B.txt" (at "link"))))
(report "status of the link" (answer status-text (file-status (at "link"))))
(report "read the link" (answer (lambda (target) target) (read-symbolic-link (at "link"))))
(report "read through the link" (read-file (at "link")))
(report "read a file as a link" (answer (lambda (target) target) (read-symbolic-link (at "a/B.txt"))))
(report "remove the link" (answer done (remove-file (at "link"))))
(report "its target remains" (show (file-exists? (at "a/B.txt"))))

;; ---- Removing a tree ----

(make-symbolic-link "a" (at "a/b/c/up"))
(report "list root before" (answer names (list-directory root)))
(report "remove the tree" (answer done (remove-tree root)))
(report "root exists" (show (file-exists? root)))
(report "remove the tree again" (answer done (remove-tree root)))

;; ---- Clock ----

(let* ((first (monotonic-nanoseconds)) (second (monotonic-nanoseconds)))
  (report "clock never runs back" (show (>= second first))))
(report "clock from a handler"
        (show (handle clock
                  ((monotonic-nanoseconds (lambda () 42)))
                (monotonic-nanoseconds))))
