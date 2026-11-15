(import
 (snail core base)
 (snail shell artifact))

(define (bundle-for (name String)) (→ Artifact-bundle)
  (artifact-bundle name))
