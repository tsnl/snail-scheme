(import (lofi base))
(def Record (datatype ( T)
                      (record (small I32 read-small) (float F32 read-float)
                              (flag Bool read-flag) (character Char read-character)
                              (function (-> T T) read-function) (value T read-value))))
(def x
     (record (ann 5 I32) (ann 2.5 F32) #t #\a (lambda (x) x) (ann 7 I64)))
(if (read-flag x) (+ (i32->i64 (read-small x)) ((read-function x) (read-value x))) (ann 0 I64))
