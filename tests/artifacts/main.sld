(import
 (snail core base)
 (snail core io)
 (only (snail shell artifact)
       ArtifactBundle)
 (rename (only (snail shell artifact) artifact-bundle) (artifact-bundle bundle))
 (generated assets)
 (sample consumer)
 (sample generic))

(define-syntax unused
  (syntax-rules ()
    ((_) (bundle "must-not-build"))))

(define-syntax admin
  (syntax-rules ()
    ((_) (bundle "admin"))))

(define (print-bundle (bundle ArtifactBundle)) (→ Unit) (! console)
  (for-each (lambda (file)
              (display (● file path))
              (display ":")
              (vector-for-each (lambda (byte) (display (u8->i32 byte)) (display ","))
                               (● file bytes))
              (newline))
            (● bundle files)))

;; These local values must not capture the imported macro's constructors.
(let ((ArtifactBundle "shadow") (ArtifactFile "shadow") (Cons "shadow") (Nil "shadow"))
  (print-bundle (bundle "client")))
(print-bundle (admin))
(print-bundle generated-bundle)
(print-bundle (client-bundle))
(print-bundle (generic-bundle "another specialization"))
