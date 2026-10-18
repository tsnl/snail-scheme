;; Concrete scalar operations and homogeneous collection libraries.
;; Static overloads specialize ordinary Lofi functions over concrete storage.
(define-library (lofi base)
  (export Default default
          + - * / sqrt truncate round floor ceiling quotient remainder = < <= > >= not unit unreachable
          i32-add i32-sub i32-mul i32-eq i32-lt i32-le i32-gt i32-ge i32-quotient i32-remainder
          i64-add i64-sub i64-mul i64-eq i64-lt i64-le i64-gt i64-ge i64-quotient i64-remainder
          i32-bitwise-and i64-bitwise-and i32-shift-right/logical i64-shift-right/logical
          i32-bitwise-xor i64-bitwise-xor
          f32-add f32-sub f32-mul f32-div f32-eq f32-lt f32-le f32-gt f32-ge f32-sqrt
          f64-add f64-sub f64-mul f64-div f64-eq f64-lt f64-le f64-gt f64-ge f64-sqrt
          f32-truncate f64-truncate f32-round f64-round f32-floor f64-floor f32-ceiling f64-ceiling
          i64->f64 i32->i64 i64->i32 f32->f64 f32->i32 f64->f32 f64->i64
          f32->bits bits->f32 f64->bits bits->f64
          ref ref-get ref-set! ref-eq? empty-list cons car cdr null?
          empty-vector make-vector vector-length vector-ref vector-set! vector-eq? vector-copy!
          vector vector-copy vector-append vector->list list->vector
          char=? char<? char<=? char>? char>=? char->integer integer->char
          make-string string-length string-ref string-set! string-eq? string-copy!
          string string-copy substring string-append string=? string->list list->string)
  (import
   (rename (lofi primitive)
           (make-vector make-filled-vector) (make-string make-filled-string)))

  ;; ---- Static numeric operators ----

  ;; Each signature becomes a static class instance. Argument and result
  ;; context select a unique row before any concrete function is emitted.
  ;; Numeric promotion is ordinary source code and calls a selected float row.
  (begin
    (define-overload + (-> I32 I32 I32) i32-add)
    (define-overload - (-> I32 I32 I32) i32-sub)
    (define-overload * (-> I32 I32 I32) i32-mul)
    (define-overload = (-> I32 I32 Bool) i32-eq)
    (define-overload < (-> I32 I32 Bool) i32-lt)
    (define-overload <= (-> I32 I32 Bool) i32-le)
    (define-overload > (-> I32 I32 Bool) i32-gt)
    (define-overload >= (-> I32 I32 Bool) i32-ge)
    (define-overload quotient (-> I32 I32 I32) i32-quotient)
    (define-overload remainder (-> I32 I32 I32) i32-remainder)

    (define-overload + (-> I64 I64 I64) i64-add)
    (define-overload - (-> I64 I64 I64) i64-sub)
    (define-overload * (-> I64 I64 I64) i64-mul)
    (define-overload = (-> I64 I64 Bool) i64-eq)
    (define-overload < (-> I64 I64 Bool) i64-lt)
    (define-overload <= (-> I64 I64 Bool) i64-le)
    (define-overload > (-> I64 I64 Bool) i64-gt)
    (define-overload >= (-> I64 I64 Bool) i64-ge)
    (define-overload quotient (-> I64 I64 I64) i64-quotient)
    (define-overload remainder (-> I64 I64 I64) i64-remainder)

    (define-overload + (-> F32 F32 F32) f32-add)
    (define-overload - (-> F32 F32 F32) f32-sub)
    (define-overload * (-> F32 F32 F32) f32-mul)
    (define-overload = (-> F32 F32 Bool) f32-eq)
    (define-overload < (-> F32 F32 Bool) f32-lt)
    (define-overload <= (-> F32 F32 Bool) f32-le)
    (define-overload > (-> F32 F32 Bool) f32-gt)
    (define-overload >= (-> F32 F32 Bool) f32-ge)
    (define-overload / (-> F32 F32 F32) f32-div)
    (define-overload sqrt (-> F32 F32) f32-sqrt)
    (define-overload truncate (-> F32 F32) f32-truncate)
    (define-overload round (-> F32 F32) f32-round)
    (define-overload floor (-> F32 F32) f32-floor)
    (define-overload ceiling (-> F32 F32) f32-ceiling)

    (define-overload + (-> F64 F64 F64) f64-add)
    (define-overload - (-> F64 F64 F64) f64-sub)
    (define-overload * (-> F64 F64 F64) f64-mul)
    (define-overload = (-> F64 F64 Bool) f64-eq)
    (define-overload < (-> F64 F64 Bool) f64-lt)
    (define-overload <= (-> F64 F64 Bool) f64-le)
    (define-overload > (-> F64 F64 Bool) f64-gt)
    (define-overload >= (-> F64 F64 Bool) f64-ge)
    (define-overload / (-> F64 F64 F64) f64-div)
    (define-overload sqrt (-> F64 F64) f64-sqrt)
    (define-overload truncate (-> F64 F64) f64-truncate)
    (define-overload round (-> F64 F64) f64-round)
    (define-overload floor (-> F64 F64) f64-floor)
    (define-overload ceiling (-> F64 F64) f64-ceiling)

    (define-overload + (-> I64 F64 F64)
      (lambda (left right) (+ (i64->f64 left) right)))
    (define-overload + (-> F64 I64 F64)
      (lambda (left right) (+ left (i64->f64 right))))
    (define-overload - (-> I64 F64 F64)
      (lambda (left right) (- (i64->f64 left) right)))
    (define-overload - (-> F64 I64 F64)
      (lambda (left right) (- left (i64->f64 right))))
    (define-overload * (-> I64 F64 F64)
      (lambda (left right) (* (i64->f64 left) right)))
    (define-overload * (-> F64 I64 F64)
      (lambda (left right) (* left (i64->f64 right))))
    (define-overload / (-> I64 F64 F64)
      (lambda (left right) (/ (i64->f64 left) right)))
    (define-overload / (-> F64 I64 F64)
      (lambda (left right) (/ left (i64->f64 right))))
    (define-overload = (-> I64 F64 Bool)
      (lambda (left right) (= (i64->f64 left) right)))
    (define-overload = (-> F64 I64 Bool)
      (lambda (left right) (= left (i64->f64 right))))
    (define-overload < (-> I64 F64 Bool)
      (lambda (left right) (< (i64->f64 left) right)))
    (define-overload < (-> F64 I64 Bool)
      (lambda (left right) (< left (i64->f64 right))))
    (define-overload <= (-> I64 F64 Bool)
      (lambda (left right) (<= (i64->f64 left) right)))
    (define-overload <= (-> F64 I64 Bool)
      (lambda (left right) (<= left (i64->f64 right))))
    (define-overload > (-> I64 F64 Bool)
      (lambda (left right) (> (i64->f64 left) right)))
    (define-overload > (-> F64 I64 Bool)
      (lambda (left right) (> left (i64->f64 right))))
    (define-overload >= (-> I64 F64 Bool)
      (lambda (left right) (>= (i64->f64 left) right)))
    (define-overload >= (-> F64 I64 Bool)
      (lambda (left right) (>= left (i64->f64 right))))

    ;; ---- Default values and homogeneous vectors ----

    (def Default (typeclass ( T) (: default (-> T))))
    (def lofi-migration-instance-1 (instance (Default I32) (default (lambda () (ann 0 I32)))))
    (def lofi-migration-instance-2 (instance (Default I64) (default (lambda () (ann 0 I64)))))
    (def lofi-migration-instance-3 (instance (Default F32) (default (lambda () (ann 0.0 F32)))))
    (def lofi-migration-instance-4 (instance (Default F64) (default (lambda () 0.0))))
    (def lofi-migration-instance-5 (instance (Default Bool) (default (lambda () #f))))
    (def lofi-migration-instance-6 (instance (Default Char) (default (lambda () #\null))))
    (def lofi-migration-instance-7 (instance (Default Unit) (default (lambda () (unit)))))

    (define-overload make-vector (All (T) (-> I64 T (Vector T))) make-filled-vector)
    ;; Returning storage from the loop keeps every fill step in tail position.
    (define-overload make-vector (All (T) (requires (Default T)) (-> I64 (Vector T)))
      (lambda (count)
        ;; Validate before user code runs; zero invokes no default. WasmGC
        ;; roots the private vector and every unfinished slot holds the first
        ;; result until replaced. The vector escapes only after full initialization.
        (if (if (< count (ann 0 I64)) #t (> count (ann 4294967295 I64)))
            (unreachable)
            (if (= count (ann 0 I64))
                (empty-vector)
                (begin (let result (make-filled-vector count (default)))
                       (begin
                         (def loop
                              (lambda (index)
                                (if (= index count)
                                    result
                                    (begin
                                      (vector-set! result index (default))
                                      (loop (+ index (ann 1 I64)))))))
                         (loop (ann 1 I64))))))))

    ;; These are ordinary polymorphic Lofi functions. Specialization keeps
    ;; each element type through Wasm allocation and bulk copying. Constructors
    ;; return fresh vectors while preserving the identity of referenced elements.
    (def vector
         (lambda elements (list->vector elements)))
    (def list->vector
         (lambda (elements)
           (if (null? elements)
               (empty-vector)
               (begin (let result (make-vector (element-count elements) (car elements)))
                      (begin
                        (def loop
                             (lambda (tail index)
                               (if (null? tail)
                                   result
                                   (begin
                                     (vector-set! result index (car tail))
                                     (loop (cdr tail) (+ index (ann 1 I64)))))))
                        (loop elements (ann 0 I64)))))))
    (def element-count
         (lambda (elements)
           (begin
             (def loop
                  (lambda (tail count)
                    (if (null? tail)
                        count
                        (if (= count (ann 4294967295 I64)) (unreachable) (loop (cdr tail) (+ count (ann 1 I64)))))))
             (loop elements (ann 0 I64)))))
    (def vector->list
         (lambda (source)
           (begin
             (def loop
                  (lambda (index result)
                    (if (= index (ann 0 I64)) result (loop (- index (ann 1 I64)) (cons (vector-ref source (- index (ann 1 I64))) result)))))
             (loop (vector-length source) (empty-list )))))
    (def vector-copy
         (lambda (source)
           (begin (let count (vector-length source))
                  (if (= count (ann 0 I64))
                      (empty-vector)
                      (begin (let result (make-vector count (vector-ref source (ann 0 I64))))
                             (begin
                               (vector-copy! result (ann 0 I64) source (ann 0 I64) count)
                               result))))))
    (def vector-append
         (lambda sources
           (begin (let count (appended-length sources))
                  (if (= count (ann 0 I64))
                      (empty-vector)
                      (begin (let result (make-vector count (first-element sources)))
                             (begin
                               (append-into! result sources (ann 0 I64))
                               result))))))
    (def appended-length
         (lambda (sources)
           ;; Check every prefix before adding another bounded Wasm length.
           ;; The addition is at most twice U32_MAX, so it cannot overflow I64.
           (begin
             (def loop
                  (lambda (tail count)
                    (if (> count (ann 4294967295 I64))
                        (unreachable)
                        (if (null? tail) count (loop (cdr tail) (+ count (vector-length (car tail))))))))
             (loop sources (ann 0 I64)))))
    (def first-element
         (lambda (sources)
           ;; A positive combined length guarantees a nonempty source will be found.
           (if (= (vector-length (car sources)) (ann 0 I64))
               (first-element (cdr sources))
               (vector-ref (car sources) (ann 0 I64)))))
    (def append-into!
         (lambda (result sources offset)
           (if (null? sources)
               (unit)
               (begin (let count (vector-length (car sources)))
                      (begin
                        (vector-copy! result offset (car sources) (ann 0 I64) count)
                        (append-into! result (cdr sources) (+ offset count)))))))

    ;; ---- Mutable Unicode strings and readonly literals ----

    ;; Storage primitives hide the permission word. Each constructor here makes
    ;; fresh mutable storage, including empty results and one-source append.
    (define-overload make-string (-> I64 Char String) make-filled-string)
    (define-overload make-string (-> I64 String)
      (lambda (count) (make-filled-string count #\null)))
    (def string
         (lambda characters (list->string characters)))
    (def list->string
         (lambda (characters)
           (begin (let result (make-string (element-count characters)))
                  (begin
                    (def loop
                         (lambda (tail index)
                           (if (null? tail)
                               result
                               (begin
                                 (string-set! result index (car tail))
                                 (loop (cdr tail) (+ index (ann 1 I64)))))))
                    (loop characters (ann 0 I64))))))
    (def string->list
         (lambda (source)
           (begin
             (def loop
                  (lambda (index result)
                    (if (= index (ann 0 I64)) result (loop (- index (ann 1 I64)) (cons (string-ref source (- index (ann 1 I64))) result)))))
             (loop (string-length source) (empty-list )))))
    (def string-copy
         (lambda (source) (substring source (ann 0 I64) (string-length source))))
    (def string-append
         (lambda sources
           (begin (let result (make-string (appended-string-length sources)))
                  (begin
                    (append-strings-into! result sources (ann 0 I64))
                    result))))
    (def appended-string-length
         (lambda (sources)
           ;; Every prefix is bounded before the next addition, which is at most
           ;; twice the maximum string length and cannot overflow I64.
           (begin
             (def loop
                  (lambda (tail count)
                    (if (> count (ann 4294967294 I64))
                        (unreachable)
                        (if (null? tail) count (loop (cdr tail) (+ count (string-length (car tail))))))))
             (loop sources (ann 0 I64)))))
    (def append-strings-into!
         (lambda (result sources offset)
           (if (null? sources)
               (unit)
               (begin (let count (string-length (car sources)))
                      (begin
                        (string-copy! result offset (car sources) (ann 0 I64) count)
                        (append-strings-into! result (cdr sources) (+ offset count)))))))
    ))
