(import
 (snail core base)
 (snail shell artifact))

(: bundle-for (-> String ArtifactBundle))
(define (bundle-for name)
  (artifact-bundle name))
