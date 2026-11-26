;; `read-resources` reads several linked files together: it starts every
;; read, waits once for all of them, and answers the bytes in the order
;; asked. The same file asked for twice is one read on the host, under
;; two tickets, which complete together.
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (snail shell static-resource)
 (snail shell static-resource serve)
 (only (snail shell http) header-values)
 (snail shell task)
 (snail shell resource))

(define (text) (→ Resource) (link-file "linked-resource.txt"))

(define (image) (→ Resource) (link-file "data/pixel.png"))

(define (alias-progress (out OutputPort)) (→ Unit)
  (let* ((file (lambda (name) (new StaticFile (name name) (digest (make-string 64 #\a)) (size 2))))
         (store (new StaticResources
                  (read (lambda (url f progress)
                          (write-line out (string-append "read " (● f name)))
                          (progress 1)
                          (Ok (new StaticBody (bytes (make-array 2 (i32->u8 7))) (cached #f))))))))
    (match (acquire-files store "resources.json" (list (file "first") (file "alias"))
                          (lambda (p) (write-line out (string-append (show (● p downloaded)) "/"
                                                                     (show (● p total))))))
      ((Err why) (panic why))
      ((Ok files)
       (write-line out (string-append (show (table-count files)) " names"))))))

(define (serve-parts (resources Resources) (out OutputPort)) (→ Unit)
  (let* ((digest (make-string 64 #\a))
         (tail (list "aa" digest))
         (old (append (list "store" "chunks") tail))
         (current (append (list "store" "chunks" "26214400") tail))
         (paths (list (append old (list "1")) (append current (list "1"))
                      (append current (list "01")) (append old (list "-1"))
                      (append current (list "one"))
                      (list "store" "chunks" "25000001" "aa" digest "1")))
         (files (map (lambda (p) (new Pair (first (string-join p "/")) (second (text)))) paths))
         (serve (static-resource-service resources files)))
    (for-each (lambda (p)
                (match (serve "GET" p)
                  ((Some r)
                   (write-line out (list-ref (header-values (● r headers) "cache-control") 0)))
                  ((None) (write-line out "no part")))) paths)))

(define (main (resources Resources) (out OutputPort)) (→ Unit)
  (for-each (lambda (bytes)
              (write-line out (string-append (show (array-length bytes))
                                             " bytes, starting "
                                             (show (u8->i32 (array-ref bytes 0))))))
            (read-resources resources (list (text) (text) (image))))
  (alias-progress out)
  (serve-parts resources out))
