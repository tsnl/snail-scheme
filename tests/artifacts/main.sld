(import
 (snail-core base)
 (snail-core io)
 (only (snail-core artifact)
       ArtifactBundle
       ArtifactBundle-files
       ArtifactFile-path
       ArtifactFile-bytes)
 (rename (only (snail-core artifact) artifact-bundle) (artifact-bundle bundle))
 (generated assets)
 (sample consumer)
 (sample generic))

(define-syntax unused
  (syntax-rules ()
    ((_) (bundle "must-not-build"))))

(define-syntax admin
  (syntax-rules ()
    ((_) (bundle "admin"))))

(: print-bundle (-> ArtifactBundle Unit ! console))
(define (print-bundle bundle)
  (for-each (lambda (file)
              (display (ArtifactFile-path file))
              (display ":")
              (vector-for-each
               (lambda (byte) (display (u8->i32 byte)) (display ","))
               (ArtifactFile-bytes file))
              (newline))
            (ArtifactBundle-files bundle)))

;; These local values must not capture the imported macro's constructors.
(let ((ArtifactBundle "shadow")
      (ArtifactFile "shadow")
      (Cons "shadow")
      (Nil "shadow"))
  (print-bundle (bundle "client")))
(print-bundle (admin))
(print-bundle generated-bundle)
(print-bundle (client-bundle))
(print-bundle (generic-bundle "another specialization"))
