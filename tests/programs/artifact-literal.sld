(import
 (snail core base)
 (snail shell artifact))

(define (bundle-for (name String)) (→ ArtifactBundle)
  (artifact-bundle name))
