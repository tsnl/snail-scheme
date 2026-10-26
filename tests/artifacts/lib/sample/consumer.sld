;; This library never requests an artifact itself. Its specialization of
;; generic-bundle must still change when that dependency embeds new bytes.
(define-library (sample consumer)
  (export client-bundle)
  (import
   (lofi base)
   (lofi artifact)
   (sample generic))
  (begin

    (: client-bundle (-> ArtifactBundle))
    (define (client-bundle)
      (generic-bundle (ann 7 I64)))

    ))
