(import
 (lofi base))

(def square (All (T) (=> ((* (-> T T T))) (-> T T)))
     (lambda (x) (* x x)))
(def distance
     (lambda (a b) (if (< a b) (- b a) (- a b))))
(def quadratic
     (lambda (a b) (+ (square a) (square b))))
(if (if (= (quadratic (ann 3 I32) (ann 4 I32)) (ann 25 I32))
        (if (= (quadratic (ann 3 I64) (ann 4 I64)) (ann 25 I64))
            (if (= (quadratic (ann 1.5 F32) (ann 2.0 F32)) (ann 6.25 F32))
                (if (= (quadratic 1.5 2.0) 6.25)
                    (if (= (distance 1.5 4.0) 2.5)
                        (= (distance (ann 4.0 F32) (ann 1.5 F32)) (ann 2.5 F32))
                        #f)
                    #f)
                #f)
            #f)
        #f)
    (ann 42 I64)
    (unreachable))
