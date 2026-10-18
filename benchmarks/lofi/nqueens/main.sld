;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.3) (cdr (cdr xs.3))))

(def length
  (lambda (xs.1)
    (((lambda () (begin (def loop.2 (lambda (xs.2 n.2) (if (null? xs.2) n.2 (loop.2 (cdr xs.2) (+ n.2 (ann 1 I64)))))) loop.2)))
      xs.1
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))



(def append (lambda (xs ys) (if (null? xs) ys (cons (car xs) (append (cdr xs) ys)))))

(def hide (lambda (count.1 x.1) (hide-i64 x.1)))

(def trace? #f)

(def nqueens
  (lambda (n)
    (begin
      (def iota1
        (lambda (n.1)
          (((lambda () (begin (def loop.1 (lambda (i.1 l) (if (= i.1 (ann 0 I64)) l (loop.1 (- i.1 (ann 1 I64)) (cons i.1 l))))) loop.1)))
            n.1
            (empty-list ))))
      (def my-try
        (lambda (x y z)
          (if (null? x)
            (if (null? y) (ann 1 I64) (ann 0 I64))
            (+
              (if (ok? (car x) (ann 1 I64) z) (my-try (append (cdr x) y) (empty-list ) (cons (car x) z)) (ann 0 I64))
              (my-try (cdr x) (cons (car x) y) z)))))
      (def ok?
        (lambda (row dist placed)
          (if (null? placed)
            #t
            (if (not (= (car placed) (+ row dist)))
              (if (not (= (car placed) (- row dist))) (ok? row (+ dist (ann 1 I64)) (cdr placed)) #f)
              #f))))
      (my-try (iota1 n) (empty-list ) (empty-list )))))

(def input0 (native-input-i64 (ann 0 I32)))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (nqueens (hide count input0))) result))) loop)))
      (ann 0 I64)
      (ann 0 I64))))

(unit)
