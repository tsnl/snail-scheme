(define-library (sample generic)
  (export generic-bundle)
  (import
   (snail core base)
   (snail shell artifact))
  (begin

    (: generic-bundle (All (A) (-> A ArtifactBundle)))
    (define (generic-bundle ignored)
      (artifact-bundle "client"))

    ))
