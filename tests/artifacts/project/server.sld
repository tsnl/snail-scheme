(import
 (snail core base)
 (snail core io)
 (rename (snail shell artifact) (artifact-bundle bundle))
 (generated assets))

(define-syntax client-snapshot
  (syntax-rules ()
    ((_) (bundle "client"))))

(define-syntax unused
  (syntax-rules ()
    ((_) (bundle "does-not-exist"))))

(: print-bytes (-> Bytes Unit ! console))
(define (print-bytes bytes)
  (vector-for-each (lambda (byte) (display (u8->i32 byte)) (display ",")) bytes)
  (newline))

(: required (-> ArtifactBundle String Bytes))
(define (required bundle name)
  (match (artifact-ref bundle name)
    ((Some bytes) bytes)
    ((None) (panic "missing artifact"))))

(define client (client-snapshot))
(display (string-join (map ArtifactFile-path (ArtifactBundle-files client)) "|"))
(newline)
(print-bytes (required client "nested/data.bin"))
(print-bytes producer-bytes)
(print-bytes (required admin-bundle "admin.bin"))
(print-bytes (required (client-snapshot) "nested/data.bin"))
