;; (snail core base) for the Chibi host: the part of the Snail-Core prelude that the
;; compiler uses, implemented with Chibi's own procedures. Lists are Chibi
;; pairs, so `Cons` and `Nil` construct and match pairs; Option and Pair are
;; structs as in Snail-Core.
(define-library (snail core base)
  (export
   define lambda if begin let let* letrec cond case when unless and or do
   define-syntax syntax-rules quote else => _ ...
   : type ann type-convert struct enum match effect handle
   + - * quotient remainder modulo = < <= > >= negate abs min max not
   unit panic drop
   i64-and i64-or i64-xor i64-shift-left i64-shift-right/logical
   i64->string string->i64 u8->i32 i32->u8 i32->i64 i64->i32 digit-value
   Option Some None Result Ok Err Never absurd Pair Pair-first Pair-second
   Cons Nil list null? length reverse append map map-indexed for-each filter fold-left fold-right
   list-ref
   list-tail
   any?
   every?
   find
   member?
   iota
   concatenate
   delete-duplicates
   take
   list-drop
   list-sort
   last
   list-index
   assoc-ref
   zip
   char->integer integer->char char=? char<? char-whitespace? char-numeric? char-alphabetic?
   string string-length string-ref string-append substring string=? string<? make-string
   string->list list->string string-join string-concatenate string-generate string-index
   string->vector vector->string
   vector-length
   vector-ref
   make-vector
   vector-generate
   vector-set
   vector-append
   vector-concatenate
   subvector
   vector-map vector-for-each vector-fold vector->list list->vector
   make-array array-length array-ref array-set! array->vector vector->array
   ref ref-get ref-set!)
  (import
   (rename (scheme base) (case scheme-case))
   (only (chibi) _ ...)
   (scheme char)
   (rename (srfi 1) (drop list-drop))
   (rename (only (srfi 132) list-stable-sort) (list-stable-sort list-sort))
   (srfi 151)
   (snail stage0 forms))
  (begin

    ;; ---- Forms ----

    ;; Snail-Core's `case` compares keys with `=`, which on strings is `string=?`.
    (define-syntax case
      (syntax-rules (else)
        ((_ key clause ...) (let ((value key)) (case-clauses value clause ...)))))

    (define-syntax case-clauses
      (syntax-rules (else)
        ((_ value (else body ...)) (begin body ...))
        ((_ value ((datum ...) body ...) clause ...)
         (if (member value (list datum ...)) (begin body ...) (case-clauses value clause ...)))))

    ;; ---- Values ----

    (define (unit) (if #f #f))

    (define (panic message) (error message))

    ;; Stage 0 has no FnOnce: the `resume` its handlers are handed cannot
    ;; resume (see (snail stage0 forms)), so dropping one releases nothing.
    (define (drop owned) (unit))

    (define (negate n) (- 0 n))

    (define (i64-and a b) (bitwise-and a b))
    (define (i64-or a b) (bitwise-ior a b))
    (define (i64-xor a b) (bitwise-xor a b))
    (define (i64-shift-left a n) (arithmetic-shift a n))
    (define (i64-shift-right/logical a n) (arithmetic-shift a (- 0 n)))

    (define (i64->string n) (number->string n))

    ;; Chibi's integers are unbounded, so conversions between widths only
    ;; wrap where Snail-Core's would: into a byte, or into 32 bits.
    (define (u8->i32 n) n)
    (define (i32->u8 n) (modulo n 256))
    (define (i32->i64 n) n)
    (define (i64->i32 n)
      (let ((low (modulo n 4294967296))) (if (>= low 2147483648) (- low 4294967296) low)))

    ;; None unless the whole text is an optionally signed decimal integer.
    (define (string->i64 text)
      (let ((n (and (> (string-length text) 0) (string->number text 10))))
        (if (exact-integer? n) (Some n) (None))))

    (enum (Result T E)
      (Ok ((value T)))
      (Err ((error E))))

    ;; No value has type Never, so `absurd` is never called: an operation
    ;; that answers Never escapes to its handler (snail stage0 forms).
    (enum Never)

    (define (absurd never)
      (error "absurd: no value has type Never" never))

    (enum (Option T)
      (Some ((value T)))
      (None))

    (struct (Pair A B)
      ((first A)
       (second B)))

    ;; ---- Lists ----

    (define (Cons head tail) (cons head tail))
    (define (Nil) '())

    ;; Snail-Core's `map` takes one list and calls `f` from left to right.
    (define (map f items)
      (let loop ((items items) (out '()))
        (if (null? items) (reverse out) (loop (cdr items) (cons (f (car items)) out)))))

    (define (zip as bs)
      (let loop ((as as) (bs bs) (out '()))
        (if (or (null? as) (null? bs))
            (reverse out)
            (loop (cdr as) (cdr bs) (cons (Pair (car as) (car bs)) out)))))

    (define (map-indexed f items)
      (let loop ((items items) (index 0) (out '()))
        (if (null? items)
            (reverse out)
            (loop (cdr items) (+ index 1) (cons (f index (car items)) out)))))

    (define (fold-left f initial items)
      (let loop ((items items) (result initial))
        (if (null? items) result (loop (cdr items) (f result (car items))))))

    (define (fold-right f initial items)
      (fold-left (lambda (result item) (f item result)) initial (reverse items)))

    (define (any? test items) (if (any test items) #t #f))
    (define (every? test items) (if (every test items) #t #f))

    (define (find test items)
      (let loop ((items items))
        (cond ((null? items) (None))
              ((test (car items)) (Some (car items)))
              (else (loop (cdr items))))))

    (define (member? value items) (if (member value items) #t #f))

    (define (concatenate lists) (fold-right append '() lists))

    (define (delete-duplicates same? items)
      (reverse (fold-left (lambda (kept item)
                            (if (any (lambda (other) (same? other item)) kept)
                                kept
                                (cons item kept)))
                          '() items)))

    (define (last items)
      (if (null? items) (None) (Some (car (reverse items)))))

    (define (assoc-ref entries key)
      (let loop ((entries entries))
        (cond ((null? entries) (None))
              ((equal? (Pair-first (car entries)) key) (Some (Pair-second (car entries))))
              (else (loop (cdr entries))))))

    (define (list-index test items)
      (let loop ((items items) (index 0))
        (cond ((null? items) (None))
              ((test (car items)) (Some index))
              (else (loop (cdr items) (+ index 1))))))

    ;; ---- Text ----

    (define (string-join texts separator)
      (if (null? texts)
          ""
          (fold-left (lambda (joined text) (string-append joined separator text))
                     (car texts)
                     (cdr texts))))

    ;; Without `apply`, which would push every string onto Chibi's stack.
    (define (string-concatenate texts)
      (let ((out (open-output-string)))
        (for-each (lambda (text) (write-string text out)) texts)
        (get-output-string out)))

    (define (string-generate count f)
      (let ((text (make-string count #\space)))
        (do ((index 0 (+ index 1))) ((= index count) text)
          (string-set! text index (f index)))))

    (define (string-index text char)
      (let loop ((index 0))
        (cond ((= index (string-length text)) (None))
              ((char=? (string-ref text index) char) (Some index))
              (else (loop (+ index 1))))))

    ;; ---- Vectors and arrays ----

    (define (vector-generate count f)
      (let ((items (make-vector count)))
        (do ((index 0 (+ index 1))) ((= index count) items)
          (vector-set! items index (f index)))))

    (define (vector-set items index value)
      (let ((copy (vector-copy items)))
        (vector-set! copy index value)
        copy))

    (define (subvector items start end) (vector-copy items start end))

    ;; Without `apply`, as `string-concatenate`.
    (define (vector-concatenate vectors)
      (let ((all (make-vector
                  (fold-left (lambda (total items) (+ total (vector-length items))) 0 vectors))))
        (fold-left
         (lambda (offset items) (vector-copy! all offset items) (+ offset (vector-length items)))
         0
         vectors)
        all))

    (define (vector-fold f initial items)
      (fold-left f initial (vector->list items)))

    (define (make-array count value) (make-vector count value))
    (define (array-length items) (vector-length items))
    (define (array-ref items index) (vector-ref items index))
    (define (array-set! items index value) (vector-set! items index value))
    (define (array->vector items) (vector-copy items))
    (define (vector->array items) (vector-copy items))

    ))
