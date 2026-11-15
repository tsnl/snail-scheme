(import
 (snail core base)
 (snail core io)
 (snail shell artifact))

(define (bundle) (→ ArtifactBundle) (artifact-bundle "client"))

(define main
  (lambda ()
    (for-each (lambda (file)
                (display (● file path))
                (display ":")
                (vector-for-each (lambda (byte) (display (u8->i32 byte)) (display ","))
                                 (● file bytes))
                (newline))
              (● (bundle) files))
    (unit)))
