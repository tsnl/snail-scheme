(import
 (lofi base)
 (lofi artifact))

(: bundle-for (-> String ArtifactBundle))
(define (bundle-for name)
  (artifact-bundle name))
