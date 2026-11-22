(import
 (snail core base))

;; A top-level value's initializer is handed nothing, so it holds no Mut
;; and can only compute: it runs once, whenever the value is first read.
(record Count
  ((value I64)))

(define count (new Count (value 0)))

(define greeting
  (begin
    (set! mut (● count value) 1)
    1))
