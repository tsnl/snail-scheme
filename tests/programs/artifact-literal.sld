(import
 (snail-core base)
 (snail-core artifact))

(: bundle-for (-> String ArtifactBundle))
(define (bundle-for name)
  (artifact-bundle name))
