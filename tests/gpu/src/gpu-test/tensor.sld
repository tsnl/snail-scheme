;; Tensor programs on the device, against the CPU's evaluation of the same
;; graph: elementwise operations through views, reductions small and in
;; levels, a matrix product, gathers and float scatters, sorts and scans,
;; and a gradient through slices. Then a line fitted by Adam, its loss read
;; back after 300 steps of one compiled program.
(define-library (gpu-test tensor)
  (export
   tensor-agreement
   swapped-params
   assigned-param
   fitted-line)
  (import
   (snail core base)
   (snail core table)
   (only (snail shell task) tasks)
   (only (snail shell gpu) gpu)
   (only (snail shell math) sin)
   (rename (snail shell tensor)
           (exp tensor-exp)
           (sin tensor-sin))
   (snail shell tensor eval)
   (snail shell tensor grad)
   (snail shell tensor compile)
   (snail shell tensor adam))
  (begin

    ;; ---- Inputs ----

    (define (wave (count I64) (scale F64)) (→ (Array F64))
      (array-generate count
                      (lambda (i) (f32->f64 (f64->f32 (* scale (sin (* 0.37 (i64->f64 i)))))))))

    (define (labels (count I64) (rows I64)) (→ (Array F64))
      (array-generate count (lambda (i) (i64->f64 (remainder (* i 7) rows)))))

    (define inputs
      (→ (Table (Array F64)))
      (fold-left (lambda (table pair) (table-set table (● pair first) (● pair second)))
                 (empty-table)
                 (list (new Pair (first "x") (second (wave (* 64 48) 2.0)))
                       (new Pair (first "w") (second (wave (* 48 8) 0.5)))
                       (new Pair (first "big") (second (wave 20000 1.0)))
                       (new Pair (first "rows") (second (labels 100 64)))
                       (new Pair
                         (first "keys")
                         (second (array-generate 3000
                                                 (lambda (i)
                                                   (i64->f64
                                                    (remainder (* i 2654435761) 65536)))))))))

    (define (params) (→ (List View))
      (list (param "x" (list 64 48) (Float))
            (param "w" (list 48 8) (Float))
            (param "big" (list 20000) (Float))
            (param "rows" (list 100) (Unsigned))
            (param "keys" (list 3000) (Unsigned))))

    ;; ---- Sinks ----

    (define (sinks) (→ (List View))
      (let* ((x (list-ref (params) 0))
             (w (list-ref (params) 1))
             (big (list-ref (params) 2))
             (rows (list-ref (params) 3))
             (keys (list-ref (params) 4))
             (loss (sum-all (square (narrow (transpose (matmul x w)) 0 2 4))))
             (sorted (sort-pairs keys (exclusive-scan (ones-like keys)) 16)))
        (list (* (tensor-exp (* (scalar 0.1) x)) (tensor-sin x))
              (where (greater x (scalar 0.5)) x (negate (absolute x)))
              (sum (transpose x) (list 1))
              (sum-all big)
              (amax big (list 0))
              (matmul x w)
              (stack (list (narrow x 1 0 8) (matmul x w) (absolute (narrow x 1 8 8))) 1)
              (scatter-add (gather x rows) rows 64)
              (list-ref (grad loss (list x)) 0)
              (● sorted first)
              (● sorted second)
              (amax (fill -2147483648.0 (list 512) (Signed)) (list 0)))))

    ;; ---- Agreement ----

    ;; Integer sinks agree exactly. Float sinks agree to a part in a thousand.

    (define (tensor-agreement) (→ String) (! gpu tasks)
      (let* ((roots (sinks))
             (program (compile-program "agreement" roots (Nil)))
             (expected (evaluate roots inputs)))
        (for-each (lambda (p)
                    (let ((name (param-label p)))
                      (write-param program
                                   name
                                   (values->bytes (table-value inputs name) (etype-of p)))))
                  (params))
        (run-program program)
        (let ((report (disagreement program roots expected 0)))
          (release-program program)
          report)))

    (define (param-label (view View)) (→ String)
      (match (● view node kind)
        ((Param name) name)
        (_ (panic "not a param"))))

    (define (table-value (table (Table (Array F64))) (key String)) (→ (Array F64))
      (match (table-ref table key)
        ((Some value) value)
        ((None) (panic key))))

    (define (values-agree? (etype Etype) (got F64) (want F64)) (→ Bool)
      (match etype
        ((Float) (< (abs (- got want)) (* 0.001 (max 1.0 (abs want)))))
        (_ (= got want))))

    (define (disagreement (program Program)
                          (roots (List View))
                          (expected (List (Array F64)))
                          (k I64))
      (→ String)
      (! gpu tasks)
      (match (new Pair (first roots) (second expected))
        ((Pair (Cons root more) (Cons want rest))
         (let* ((got (bytes->values (read-sink program k) (etype-of root)))
                (bad (find (lambda (i)
                             (not
                              (values-agree? (etype-of root) (array-ref got i) (array-ref want i))))
                           (iota (array-length want)))))
           (match bad
             ((Some i)
              (string-append "sink " (show k) " element " (show i) ": "
                             (f64->string (array-ref got i))
                             " not "
                             (f64->string (array-ref want i))))
             ((None) (disagreement program more rest (+ k 1))))))
        (_ (string-append (show k) " sinks agree"))))

    ;; ---- Parameter updates ----

    (define (signed-words (bytes Bytes)) (→ String)
      (string-join (map (lambda (x) (show (f64->i64 x)))
                        (array->list (bytes->values bytes (Signed))))
                   " "))

    ;; A takes B transposed, B takes A, and the sink keeps A before the swap.
    (define (swapped-params) (→ String) (! gpu tasks)
      (let* ((a (param "a" (list 2 2) (Signed)))
             (b (param "b" (list 2 2) (Signed)))
             (program (compile-program "swap" (list a)
                                       (list (new Pair (first a) (second (transpose b)))
                                             (new Pair (first b) (second a))))))
        (write-param program "a" (values->bytes (list->array (list 1.0 2.0 3.0 4.0)) (Signed)))
        (write-param program "b" (values->bytes (list->array (list 5.0 6.0 7.0 8.0)) (Signed)))
        (run-program program)
        (let ((report (string-join (list (signed-words (read-param program "a"))
                                         (signed-words (read-param program "b"))
                                         (signed-words (read-sink program 0)))
                                   " / ")))
          (release-program program)
          report)))

    ;; An assignment can be the only reference to the destination.
    (define (assigned-param) (→ String) (! gpu tasks)
      (let* ((a (param "a" (Nil) (Signed)))
             (program (compile-program "assign" (Nil)
                                       (list
                                        (new Pair (first a) (second (fill 9.0 (Nil) (Signed))))))))
        (run-program program)
        (let ((report (signed-words (read-param program "a"))))
          (release-program program)
          report)))

    ;; ---- Training ----

    ;; y = 2 x0 - 3 x1 + 0.5 x2 + 1 over 256 points, fitted from zeros.

    (define (fitted-line) (→ String) (! gpu tasks)
      (let* ((x (param "points" (list 256 3) (Float)))
             (y (param "targets" (list 256 1) (Float)))
             (w (param "w" (list 3 1) (Float)))
             (b (param "b" (list 1) (Float)))
             (loss (mean (square (- (+ (matmul x w) b) y))))
             (grads (grad loss (list w b)))
             (updates (adam-updates "adam"
                                    (adam 0.9 0.999 1e-8)
                                    (list (new Trained
                                            (param w)
                                            (grad (list-ref grads 0))
                                            (rate (scalar 0.05)))
                                          (new Trained
                                            (param b)
                                            (grad (list-ref grads 1))
                                            (rate (scalar 0.05))))))
             (program (compile-program "fit" (list loss) updates))
             (points (wave (* 256 3) 1.0)))
        (write-param program "points" (values->bytes points (Float)))
        (write-param program
                     "targets"
                     (values->bytes (array-generate 256 (lambda (i) (target points i))) (Float)))
        (run-program program)
        (let ((first-loss (array-ref (bytes->values (read-sink program 0) (Float)) 0)))
          (for-each (lambda (_) (run-program program)) (iota 1000))
          (let ((last-loss (array-ref (bytes->values (read-sink program 0) (Float)) 0))
                (b-value (array-ref (bytes->values (read-param program "b") (Float)) 0)))
            (release-program program)
            (string-append (if (> first-loss 1.0) "from above 1" "from below 1")
                           (if (< last-loss 0.0001)
                               " to below 1e-4"
                               (string-append " to " (f64->string last-loss)))
                           ", b "
                           (f64->string (/ (round (* b-value 100.0)) 100.0)))))))

    (define (target (points (Array F64)) (i I64)) (→ F64)
      (+ 1.0
         (+ (* 2.0 (array-ref points (* 3 i)))
            (+ (* -3.0 (array-ref points (+ (* 3 i) 1)))
               (* 0.5 (array-ref points (+ (* 3 i) 2)))))))

    ))
