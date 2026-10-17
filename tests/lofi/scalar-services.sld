(import (lofi base) (lofi math) (lofi text))

;; ---- Concrete scalar calls retain their public ABI ----

(def unary (-> I64 F64 F64)
     (lambda (operation value)
       (if (= operation (ann 0 I64)) (exp value)
           (if (= operation (ann 1 I64)) (log value)
               (if (= operation (ann 2 I64)) (tan value)
                   (if (= operation (ann 3 I64)) (asin value)
                       (if (= operation (ann 4 I64)) (acos value)
                           (if (= operation (ann 5 I64)) (floor value)
                               (if (= operation (ann 6 I64)) (ceiling value)
                                   (if (= operation (ann 7 I64))
                                       (f32->f64 (floor (f64->f32 value)))
                                       (f32->f64 (ceiling (f64->f32 value)))))))))))))

(def binary (-> I64 F64 F64 F64)
     (lambda (operation left right)
       (if (= operation (ann 0 I64)) (atan2 left right) (pow left right))))

(def character (-> I64 Char I64)
     (lambda (operation value)
       (if (= operation (ann 0 I64)) (char->integer (char-upcase value))
           (if (= operation (ann 1 I64)) (char->integer (char-foldcase value))
               (if (char-lower-case? value) (ann 1 I64) (ann 0 I64))))))

(unit)
