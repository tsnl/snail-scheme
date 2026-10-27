(define-library (sample generic)
  (export generic-bundle)
  (import
   (snail-core base)
   (snail-core artifact))
  (begin

    (: generic-bundle (All (A) (-> A ArtifactBundle)))
    (define (generic-bundle ignored)
      (artifact-bundle "client"))

    ))
