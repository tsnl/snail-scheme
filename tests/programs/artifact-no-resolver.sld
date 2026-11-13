(import
 (snail core base)
 (snail shell artifact))

(define main
  (lambda ()
    (artifact-bundle "client")
    (unit)))
