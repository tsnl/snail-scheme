(define-library (sample generic)
  (export generic-bundle)
  (import
   (lofi base)
   (lofi artifact))
  (begin

    (: generic-bundle (All (A) (-> A ArtifactBundle)))
    (define (generic-bundle ignored)
      (artifact-bundle "client"))

    ))
