;; A server's view of the client it embeds: each file's path and size, and
;; the bytes of one.
(import
 (snail core base)
 (snail core io)
 (snail shell resource)
 (embedded client))

(for-each (lambda (file)
            (write-line (string-append (● file first)
                                       " "
                                       (show (array-length (read-resource (● file second)))))))
          (client-files))
(match (find (lambda (file) (string=? (● file first) "nested/data.bin")) (client-files))
  ((Some file)
   (write-line (string-join (map (lambda (byte) (show (u8->i32 byte)))
                                 (array->list (read-resource (● file second))))
                            ",")))
  ((None) (panic "the client has no nested/data.bin")))
