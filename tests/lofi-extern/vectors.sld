(import
 (lofi base))
(define-extern collect "probe" "callback" (-> Unit))
(def data
     (vector (ann 0 I64) (ann 1 I64) (ann 2 I64) (ann 3 I64) (ann 4 I64) (ann 5 I64)))
(def trace
     (ref (ann 0 I64)))
(def mark
     (lambda (digit) (ref-set! trace (+ (* (ref-get trace) (ann 10 I64)) digit))))

(def worker (-> I32 I32)
     (lambda (x) x))

(def read (-> I64 I64)
     (lambda (index) (vector-ref data index)))

(def marks (-> I64)
     (lambda () (ref-get trace)))

(def reset (-> Unit)
     (lambda ()
       (begin
         (ref-set! trace (ann 0 I64))
         (begin
           (def loop
                (lambda (index)
                  (if (= index (ann 6 I64))
                      (unit)
                      (begin
                        (vector-set! data index index)
                        (loop (+ index (ann 1 I64)))
                        (unit)))))
           (loop (ann 0 I64))))))

(def write (-> I64 Unit)
     (lambda (index)
       ((begin (mark (ann 4 I64)) vector-set!)
        (begin (mark (ann 1 I64)) data)
        (begin (mark (ann 2 I64)) index)
        (begin (mark (ann 3 I64)) (ann 99 I64)))))

(def allocate (-> I64 I64)
     (lambda (count)
       (vector-length (make-vector (begin (mark (ann 1 I64)) count) (begin (mark (ann 2 I64)) (ann 42 I64))))))

(def copy (-> I64 I64 I64 Unit)
     (lambda (at start end)
       ((begin (mark (ann 6 I64)) vector-copy!)
        (begin (mark (ann 1 I64)) data) (begin (mark (ann 2 I64)) at)
        (begin (mark (ann 3 I64)) data) (begin (mark (ann 4 I64)) start) (begin (mark (ann 5 I64)) end))))

(def gc-check (-> I64)
     (lambda ()
       (begin (let cell (ref (ann 42 I64)))
              (begin (let values (make-vector (ann 2 I64) cell))
                     (begin
                       (collect)
                       (ref-set! (vector-ref values (ann 0 I64)) (ann 43 I64))
                       (ref-get (vector-ref values (ann 1 I64))))))))
(ann 42 I64)
