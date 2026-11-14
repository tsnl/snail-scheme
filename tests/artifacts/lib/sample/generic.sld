(define-library (sample generic)
  (export generic-bundle)
  (import
   (snail core base)
   (snail shell artifact))
  (begin

    (define (generic-bundle (ignored A)) (→ ArtifactBundle) (∀ (A))
      (artifact-bundle "client"))

    ))
