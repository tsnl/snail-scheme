(import
 (snail-core base)
 (snail-core io))

;; Call-site inclusion must not silently widen function values.
(: widen (All (A e) (-> (-> A ! e) (-> A ! console e))))
(define (widen action) action)
