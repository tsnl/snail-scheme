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

(define (print-bytes (bytes Bytes)) (→ Unit) (! output-port)
  (vector-for-each (lambda (byte) (display (u8->i32 byte)) (display ",")) bytes)
  (newline))

(define (required (bundle ArtifactBundle) (name String)) (→ Bytes)
  (match (artifact-ref bundle name)
    ((Some bytes) bytes)
    ((None) (panic "missing artifact"))))

(define client (client-snapshot))

(define main
  (lambda ()
    (display (string-join (map (lambda (record) (● record path)) (● client files)) "|"))
    (newline)
    (print-bytes (required client "nested/data.bin"))
    (print-bytes producer-bytes)
    (print-bytes (required admin-bundle "admin.bin"))
    (print-bytes (required (client-snapshot) "nested/data.bin"))
    (unit)))
