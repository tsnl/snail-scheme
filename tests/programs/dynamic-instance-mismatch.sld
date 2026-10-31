(import
 (snail core base)
 (snail core io))

(instance (Num Any)
  (dispatch I64 F64))

(: left Any)
(define left 1)
(: right Any)
(define right 2.0)
(+ left right)
