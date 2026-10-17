;; Canonical bare Lofi. See migration.json for source provenance.

(import (lofi base))

(def cddr (lambda (xs.2) (cdr (cdr xs.2))))

(def length
  (lambda (xs)
    (((lambda () (begin (def loop.15 (lambda (xs.1 n.3) (if (null? xs.1) n.3 (loop.15 (cdr xs.1) (+ n.3 (ann 1 I64)))))) loop.15)))
      xs
      (ann 0 I64))))

(define-extern native-input-i64 "benchmark" "input_i64" (-> I32 I64))

(define-extern native-input-f64 "benchmark" "input_f64" (-> I32 F64))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(define-extern hide-i64 "benchmark" "hide_i64" (-> I64 I64))

(define-extern hide-f64 "benchmark" "hide_f64" (-> F64 F64))

(def PuzzleResult (datatype () (puzzle-failed) (puzzle-count (value I64))))

(def puzzle-failure (puzzle-failed))

(def zero? (lambda (value.4) (= value.4 (ann 0 I64))))

(define-extern puzzle-print "benchmark" "print_text" (-> I64 Unit))

(def puzzle-error (lambda () (begin (puzzle-print (ann 0 I64)) (puzzle-print (ann 1 I64)))))

(def puzzle-for-each
  (lambda (procedure values)
    (if (null? values)
      (unit)
      (begin (procedure (car values)) (puzzle-for-each procedure (cdr values)) (unit)))))

(def hide (lambda (count.1 x) (hide-i64 x)))

(def my-iota
  (lambda (n.1)
    (((lambda () (begin (def loop.14 (lambda (n.2 list) (if (zero? n.2) list (loop.14 (- n.2 (ann 1 I64)) (cons (- n.2 (ann 1 I64)) list))))) loop.14)))
      n.1
      (empty-list ))))

(def *size* (ann 511 I64))

(def classmax (ann 3 I64))

(def typemax (ann 12 I64))

(def *iii* (ref (ann 0 I64)))

(def *kount* (ref (ann 0 I64)))

(def *d* (ann 8 I64))

(def *piececount* (make-vector (+ classmax (ann 1 I64)) (ann 0 I64)))

(def *class* (make-vector (+ typemax (ann 1 I64)) (ann 0 I64)))

(def *piecemax* (make-vector (+ typemax (ann 1 I64)) (ann 0 I64)))

(def *puzzle* (make-vector (+ *size* (ann 1 I64)) #t))

(def *p* (make-vector (+ typemax (ann 1 I64)) (make-vector (ann 0 I64) #t)))

(def fit
  (lambda (i.8 j.5)
    ((lambda (end.2) (((lambda () (begin (def loop.13 (lambda (k.6) (if ((lambda (value.3) (if value.3 value.3 (if (vector-ref (vector-ref *p* i.8) k.6) (vector-ref *puzzle* (+ j.5 k.6)) #f))) (> k.6 end.2)) (if (> k.6 end.2) #t #f) (loop.13 (+ k.6 (ann 1 I64)))))) loop.13))) (ann 0 I64)))
      (vector-ref *piecemax* i.8))))

(def place
  (lambda (i.7 j.4)
    ((lambda (end.1) (begin (((lambda () (begin (def loop.12 (lambda (k.5) (if (> k.5 end.1) (unit) (begin (if (vector-ref (vector-ref *p* i.7) k.5) (begin (vector-set! *puzzle* (+ j.4 k.5) #t) (unit)) (unit)) (loop.12 (+ k.5 (ann 1 I64))))))) loop.12))) (ann 0 I64)) (vector-set! *piececount* (vector-ref *class* i.7) (- (vector-ref *piececount* (vector-ref *class* i.7)) (ann 1 I64))) (((lambda () (begin (def loop.11 (lambda (k.4) (if ((lambda (value.2) (if value.2 value.2 (not (vector-ref *puzzle* k.4)))) (> k.4 *size*)) (if (> k.4 *size*) (ann 0 I64) k.4) (loop.11 (+ k.4 (ann 1 I64)))))) loop.11))) j.4)))
      (vector-ref *piecemax* i.7))))

(def puzzle-remove
  (lambda (i.6 j.3)
    ((lambda (end) (begin (((lambda () (begin (def loop.10 (lambda (k.3) (if (> k.3 end) (unit) (begin (if (vector-ref (vector-ref *p* i.6) k.3) (begin (vector-set! *puzzle* (+ j.3 k.3) #f) (unit)) (unit)) (loop.10 (+ k.3 (ann 1 I64))))))) loop.10))) (ann 0 I64)) (vector-set! *piececount* (vector-ref *class* i.6) (+ (vector-ref *piececount* (vector-ref *class* i.6)) (ann 1 I64)))))
      (vector-ref *piecemax* i.6))))

(def trial
  (lambda (j.2)
    (((lambda () (begin (def candidates (lambda (i.5) (if (> i.5 typemax) (begin (ref-set! *kount* (+ (ref-get *kount*) (ann 1 I64))) #f) (if (if (not (zero? (vector-ref *piececount* (vector-ref *class* i.5)))) (fit i.5 j.2) #f) ((lambda (k.2) (if ((lambda (value.1) (if value.1 value.1 (zero? k.2))) (trial k.2)) (begin (ref-set! *kount* (+ (ref-get *kount*) (ann 1 I64))) #t) (begin (puzzle-remove i.5 j.2) (candidates (+ i.5 (ann 1 I64)))))) (place i.5 j.2)) (candidates (+ i.5 (ann 1 I64))))))) candidates)))
      (ann 0 I64))))

(def definePiece
  (lambda (iclass ii jj kk)
    ((lambda (index) (begin (((lambda () (begin (def loop.7 (lambda (i.4) (if (> i.4 ii) (unit) (begin (((lambda () (begin (def loop.8 (lambda (j.1) (if (> j.1 jj) (unit) (begin (((lambda () (begin (def loop.9 (lambda (k.1) (if (> k.1 kk) (unit) (begin (ref-set! index (+ i.4 (* *d* (+ j.1 (* *d* k.1))))) (vector-set! (vector-ref *p* (ref-get *iii*)) (ref-get index) #t) (loop.9 (+ k.1 (ann 1 I64))))))) loop.9))) (ann 0 I64)) (loop.8 (+ j.1 (ann 1 I64))))))) loop.8))) (ann 0 I64)) (loop.7 (+ i.4 (ann 1 I64))))))) loop.7))) (ann 0 I64)) (vector-set! *class* (ref-get *iii*) iclass) (vector-set! *piecemax* (ref-get *iii*) (ref-get index)) (if (not (= (ref-get *iii*) typemax)) (begin (ref-set! *iii* (+ (ref-get *iii*) (ann 1 I64))) (unit)) (unit))))
      (ref (ann 0 I64)))))

(def start
  (lambda (size)
    (begin
      (ref-set! *kount* (ann 0 I64))
      (((lambda () (begin (def loop.6 (lambda (m.2) (if (> m.2 size) (unit) (begin (vector-set! *puzzle* m.2 #t) (loop.6 (+ m.2 (ann 1 I64))))))) loop.6)))
        (ann 0 I64))
      (((lambda () (begin (def loop.3 (lambda (i.3) (if (> i.3 (ann 5 I64)) (unit) (begin (((lambda () (begin (def loop.4 (lambda (j) (if (> j (ann 5 I64)) (unit) (begin (((lambda () (begin (def loop.5 (lambda (k) (if (> k (ann 5 I64)) (unit) (begin (vector-set! *puzzle* (+ i.3 (* *d* (+ j (* *d* k)))) #f) (loop.5 (+ k (ann 1 I64))))))) loop.5))) (ann 1 I64)) (loop.4 (+ j (ann 1 I64))))))) loop.4))) (ann 1 I64)) (loop.3 (+ i.3 (ann 1 I64))))))) loop.3)))
        (ann 1 I64))
      (((lambda () (begin (def loop.1 (lambda (i.2) (if (> i.2 typemax) (unit) (begin (((lambda () (begin (def loop.2 (lambda (m.1) (if (> m.1 size) (unit) (begin (vector-set! (vector-ref *p* i.2) m.1 #f) (loop.2 (+ m.1 (ann 1 I64))))))) loop.2))) (ann 0 I64)) (loop.1 (+ i.2 (ann 1 I64))))))) loop.1)))
        (ann 0 I64))
      (ref-set! *iii* (ann 0 I64))
      (definePiece (ann 0 I64) (ann 3 I64) (ann 1 I64) (ann 0 I64))
      (definePiece (ann 0 I64) (ann 1 I64) (ann 0 I64) (ann 3 I64))
      (definePiece (ann 0 I64) (ann 0 I64) (ann 3 I64) (ann 1 I64))
      (definePiece (ann 0 I64) (ann 1 I64) (ann 3 I64) (ann 0 I64))
      (definePiece (ann 0 I64) (ann 3 I64) (ann 0 I64) (ann 1 I64))
      (definePiece (ann 0 I64) (ann 0 I64) (ann 1 I64) (ann 3 I64))
      (definePiece (ann 1 I64) (ann 2 I64) (ann 0 I64) (ann 0 I64))
      (definePiece (ann 1 I64) (ann 0 I64) (ann 2 I64) (ann 0 I64))
      (definePiece (ann 1 I64) (ann 0 I64) (ann 0 I64) (ann 2 I64))
      (definePiece (ann 2 I64) (ann 1 I64) (ann 1 I64) (ann 0 I64))
      (definePiece (ann 2 I64) (ann 1 I64) (ann 0 I64) (ann 1 I64))
      (definePiece (ann 2 I64) (ann 0 I64) (ann 1 I64) (ann 1 I64))
      (definePiece (ann 3 I64) (ann 1 I64) (ann 1 I64) (ann 1 I64))
      (vector-set! *piececount* (ann 0 I64) (ann 13 I64))
      (vector-set! *piececount* (ann 1 I64) (ann 3 I64))
      (vector-set! *piececount* (ann 2 I64) (ann 1 I64))
      (vector-set! *piececount* (ann 3 I64) (ann 1 I64))
      ((lambda (m n) (begin (if (fit (ann 0 I64) m) (ref-set! n (place (ann 0 I64) m)) (puzzle-error)) (if (trial (ref-get n)) (puzzle-count (ref-get *kount*)) puzzle-failure)))
        (+ (* *d* (+ *d* (ann 1 I64))) (ann 1 I64))
        (ref (ann 0 I64))))))

(puzzle-for-each
  (lambda (i.1) (vector-set! *p* i.1 (make-vector (+ *size* (ann 1 I64)) #t)))
  (my-iota (+ typemax (ann 1 I64))))

(def input0 (native-input-i64 (ann 0 I32)))

(def input1 (native-input-i64 (ann 1 I32)))

(def input2 (native-input-i64 (ann 2 I32)))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (i result) (if (< i count) (loop (+ i (ann 1 I64)) (start (hide count input0))) (if (match result ((puzzle-failed) (= input1 (ann 0 I64))) ((puzzle-count value) (if (= input1 (ann 2 I64)) (= value input2) #f))) (ann 1 I64) (ann 0 I64))))) loop)))
      (ann 0 I64)
      puzzle-failure)))

(unit)
