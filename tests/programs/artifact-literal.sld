(import
 (snail core base)
 (snail shell artifact))

(: bundle-for (impl (Fn String -> ArtifactBundle)))
(define (bundle-for name)
  (artifact-bundle name))
