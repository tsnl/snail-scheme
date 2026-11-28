;; Give the publisher each oversized regular file's physical address. The
;; shared blob writer owns the representation, including its exact cutoff.
(import
 (snail core base)
 (snail core io)
 (snail shell blob-store)
 (snail shell json)
 (snail shell json read))

(define (field (name String) (value Json)) (→ (Pair String Json))
  (new Pair (first name) (second value)))

(define (store-file (fs Fs) (root String) (path String)) (→ (List Json))
  (match (followed-status fs path)
    ((Err why) (panic (string-append path ": " (show why))))
    ((Ok status)
     (if (<= (● status size) blob-part-size) (Nil)
         (match (store-file! fs root path (● status size) (None))
           ((Err why) (panic why))
           ((Ok digest)
            (list (JsonObject (list (field "path" (JsonString path))
                                    (field "size" (JsonInteger (● status size)))
                                    (field "sha256" (JsonString digest))
                                    (field "directory"
                                           (JsonString (blob-directory digest))))))))))))

(define (file-path (value Json)) (→ String)
  (match value ((JsonString path) path) (_ (panic "expected a file path"))))

(define (input-paths (in InputPort)) (→ (List String))
  (match (read-line in)
    ((Some line) (match (string->json line)
                   ((Some (JsonArray paths)) (map file-path paths))
                   (_ (panic "expected an array of file paths"))))
    ((None) (panic "missing file paths"))))

(define (main (fs Fs) (in InputPort) (out OutputPort) (args Arguments)) (→ Unit)
  (match (command-line args)
    ((Cons _ (Cons root (Nil)))
     (let ((files (concatenate (map (lambda (p) (store-file fs root p)) (input-paths in)))))
       (write-line out (json->string
                        (JsonObject (list (field "partSize" (JsonInteger blob-part-size))
                                          (field "files" (JsonArray files))))))))
    (_ (panic "expected a destination object store"))))
