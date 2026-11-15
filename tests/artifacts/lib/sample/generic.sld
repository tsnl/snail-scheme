(define-library (sample generic)
  (export generic-bundle)
  (import
   (snail core base)
   (snail shell artifact))
  (begin

    (define (generic-bundle (ignored A)) (→ Artifact-bundle) (∀ (A))
      (artifact-bundle "client"))

    ))
