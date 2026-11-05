(import
 (snail core base)
 (snail core io))

(define root "build/tests/files-create")
(remove-tree root)
(make-directories root)

(: report (-> (Result Unit FileError) Unit ! console))
(define (report result)
  (write-line (match result ((Ok _) "created") ((Err (AlreadyExists)) "exists") (_ "failed"))))

(report (make-file (string-append root "/new.txt")))
(write-file (string-append root "/new.txt") "kept")
(report (make-file (string-append root "/new.txt")))
(write-line (read-file (string-append root "/new.txt")))
(make-symbolic-link "missing" (string-append root "/link.txt"))
(report (make-file (string-append root "/link.txt")))
(write-line (show (file-exists? (string-append root "/missing"))))
(remove-tree root)
