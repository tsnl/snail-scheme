(import
 (lofi base)
 (lofi io)
 (lofi datum)
 (lofi read)
 (lofi write)
 (lofi bytes))

;; ---- Complete readable and displayed streams preserve the input data ----

(def copy-output (-> I64)
     (lambda ()
       (call-with-input-file "input.scm"
         (lambda (input)
           (call-with-output-file "written.scm"
             (lambda (written)
               (call-with-output-file "displayed.txt"
                 (lambda (shown)
                   (begin
                     (def loop
                          (lambda (count)
                            (begin (let result (read input))
                                   (if (read-end? result)
                                       count
                                       (begin (let value (read-value! result))
                                              (begin
                                                (write value written) (newline written)
                                                (display value shown) (newline shown) (loop (+ count (ann 1 I64)))))))))
                     (loop (ann 0 I64)))))))))))

(def roundtrip (-> Bool)
     (lambda ()
       (call-with-input-file "input.scm"
         (lambda (first)
           (call-with-input-file "written.scm"
             (lambda (second)
               (begin
                 (def loop
                      (lambda ()
                        (begin (let lofi-migration-let-1 (read first)) (let lofi-migration-let-2 (read second))
                               (let left lofi-migration-let-1)
                               (let right lofi-migration-let-2)
                               (if (read-end? left)
                                   (read-end? right)
                                   (if (not (read-end? right))
                                       (if (datum=? (read-value! left) (read-value! right)) (loop) #f)
                                       #f)))))
                 (loop))))))))

;; ---- Shared storage, cyclic diagnostics and fresh per-call labels ----

(def named (-> String Datum)
     (lambda (text) (datum-symbol (string->symbol text))))

(def output-line (-> Datum OutputPort Unit)
     (lambda (value port)
       (begin (write-datum value port) (newline port))))

(def cyclic-sharing (-> OutputPort Unit)
     (lambda (port)
       (begin (let first (ref (named "a")))
              (begin (let rest (ref (datum-null)))
                     (begin (let pair (datum-pair first rest))
                            (begin (let alias (datum-pair first rest))
                                   (begin (let text (string-copy "s"))
                                          (begin (let bytes (bytevector (ann 1 I64) (ann 2 I64)))
                                                 (begin (let values (vector pair alias (datum-string text) (datum-string text)
                                                                            (datum-bytevector bytes) (datum-bytevector bytes) (datum-null)))
                                                        (begin (let root (datum-vector values))
                                                               (begin
                                                                 (vector-set! values (ann 6 I64) root)
                                                                 (output-line root port) (output-line root port)
                                                                 (if (if (datum-eq? pair alias)
                                                                         (if (datum-eq? (vector-ref values (ann 6 I64)) root)
                                                                             (if (string=? text "s") (= (bytevector-u8-ref bytes (ann 1 I64)) (ann 2 I64)) #f)
                                                                             #f)
                                                                         #f)
                                                                     (unit)
                                                                     (begin (unreachable)
                                                                            (unit))))))))))))))

(def shared-tail (-> OutputPort Unit)
     (lambda (port)
       (begin (let tail (datum-list (named "b") (named "c")))
              (begin (let values (vector (datum-cons (named "a") tail) tail (datum-null)))
                     (begin (let root (datum-vector values))
                            (begin
                              (vector-set! values (ann 2 I64) (datum-vector values))
                              (output-line root port)))))))

(def graphs (-> Unit)
     (lambda ()
       (call-with-output-file "graphs.txt"
         (lambda (port)
           (begin
             (begin (let pair (datum-cons (named "a") (datum-null)))
                    (begin
                      (output-line (datum-vector (vector pair pair)) port)
                      (datum-set-cdr! pair pair) (output-line pair port)
                      (datum-set-car! pair pair) (output-line pair port)
                      (display-datum pair port) (newline port)))
             (begin (let values (vector (named "a") (datum-null)))
                    (begin (let root (datum-vector values))
                           (begin
                             (vector-set! values (ann 1 I64) root) (output-line root port))))
             (cyclic-sharing port) (shared-tail port))))))

(def deep-output (-> Unit)
     (lambda ()
       (call-with-output-file "deep.txt"
         (lambda (port)
           (begin
             (def loop
                  (lambda (depth value)
                    (if (= depth (ann 0 I64))
                        (output-line value port)
                        (loop (- depth (ann 1 I64)) (datum-list (datum-vector (vector value)))))))
             (loop (ann 4096 I64) (named "end")))))))

;; ---- Stdout identity and borrowing survive both close entry points ----

(define-extern raw-close "snail.library" "snail:io/close" (-> I32 Unit))
(define-extern raw-write "snail.library" "snail:io/write-character" (-> I32 I32 Unit))
(define-extern raw-read "snail.library" "snail:io/read-character" (-> I32 I32))

(def stdout-check (-> Unit)
     (lambda ()
       (begin (let lofi-migration-let-3 (current-output-port)) (let lofi-migration-let-4 (open-output-file "identity.txt"))
              (let port lofi-migration-let-3)
              (let file lofi-migration-let-4)
              (begin
                (if (if (output-port=? port (current-output-port))
                        (if (output-port=? file file) (not (output-port=? port file)) #f)
                        #f)
                    (unit)
                    (begin (unreachable)
                           (unit)))
                (close-output-port file) (close-output-port port) (raw-close (ann -2 I32))
                (write-string "stdout:") (display (datum-string "λ😀")) (write-char #\space)
                (write (datum-list (named "a") (datum-string "b"))) (newline)
                (write-string "borrowed:" port) (write-char #\! port) (newline port)
                (close-output-port (current-output-port))
                (write (datum-null)) (newline)))))

;; ---- Each failure owns a fresh terminal invocation ----

(def pending-file (-> Unit)
     (lambda ()
       (begin (let file (open-output-file "pending.txt")) (write-string "buffered" file))))

(def closed-empty (-> Unit)
     (lambda ()
       (begin (let file (open-output-file "closed.txt"))
              (begin
                (close-output-port file) (display (datum-string "") file)))))

(def callback-trap (-> Unit)
     (lambda ()
       (begin
         (pending-file) (display (datum-string "before trap")) (unreachable))))

(def invalid-character (-> Unit)
     (lambda ()
       (begin (pending-file) (raw-write (ann -2 I32) (ann 55296 I32)))))

(def invalid-handle (-> Unit)
     (lambda ()
       (begin (pending-file) (raw-write (ann -3 I32) (ann 65 I32)))))

(def read-stdout (-> Unit)
     (lambda ()
       (begin (pending-file) (raw-read (ann -2 I32)) (unit))))

(def stdout-failure (-> Unit)
     (lambda ()
       (begin (pending-file) (write-string "failed output"))))
(unit)
