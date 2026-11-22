;; An update of the right byte length can still have the wrong element type.
(import
 (snail core base)
 (snail shell gpu record)
 (snail shell tensor)
 (snail shell tensor lower))

(with-recorded-gpu
 (lambda ()
   (lower "update"
          (Nil)
          (list
           (new Pair (first (param "counter" (Nil) (Signed))) (second (scalar 1.0)))))
   (unit)))
