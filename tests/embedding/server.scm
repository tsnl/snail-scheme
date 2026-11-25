;; A server's view of the client it embeds: each file's path and size, and
;; the bytes of one.
(import
 (snail core base)
 (snail core io)
 (snail shell resource)
 (snail shell static-resource serve)
 (only (snail shell http) parse-target header-values Target)
 (only (snail shell http exchange) Response)
 (embedded client))

(define (main (out OutputPort) (resources Resources)) (→ Unit)
  (let* ((files (client-files)) (serve (static-resource-service resources files)))
    (for-each
     (lambda (file)
       (let* ((path (● file first))
              (parts (match (parse-target (string-append "/" path))
                       ((Ok t) (● t path)) ((Err _) (panic "invalid path")))))
         (match (serve "GET" parts)
           ((Some response)
            (write-line out (string-join (list path (show (array-length (● response body)))
                                               (show (● response status))
                                               (list-ref
                                                (header-values (● response headers) "cache-control")
                                                0))
                                         " ")))
           ((None)
            (write-line out
                        (string-append path
                                       " "
                                       (show (array-length
                                              (read-resource resources (● file second))))))))))
     files))
  (match (find (lambda (file) (string=? (● file first) "nested/data.bin")) (client-files))
    ((Some file)
     (write-line out
                 (string-join (map (lambda (byte) (show (u8->i32 byte)))
                                   (array->list (read-resource resources (● file second))))
                              ",")))
    ((None) (panic "the client has no nested/data.bin"))))
