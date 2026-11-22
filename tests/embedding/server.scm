;; A server's view of the client it embeds: each file's path and size, and
;; the bytes of one.
(import
 (snail core base)
 (snail core io)
 (snail shell resource)
 (embedded client))

(define (main (out OutputPort) (resources Resources)) (→ Unit) (! mut)
  (for-each (lambda (file)
              (write-line out
                          (string-append (● file first)
                                         " "
                                         (show (array-length (read-resource resources
                                                                            (● file second)))))))
            (client-files))
  (match (find (lambda (file) (string=? (● file first) "nested/data.bin")) (client-files))
    ((Some file)
     (write-line out
                 (string-join (map (lambda (byte) (show (u8->i32 byte)))
                                   (array->list (read-resource resources (● file second))))
                              ",")))
    ((None) (panic "the client has no nested/data.bin"))))
