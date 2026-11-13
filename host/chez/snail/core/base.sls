;; The compiler's standard-library boundary on Chez. Records use the same
;; mutable reference semantics as compiled code; host pairs represent Lists.
(library (snail core base)
  (export
   ● test-base
   define lambda if begin let let* letrec cond case when unless and or do
   define-syntax syntax-rules quote else => _ ...
   type ann struct enum match effect handle
   +
   -
   *
   /
   sqrt
   floor
   ceiling
   truncate
   round
   quotient
   remainder
   modulo
   =
   <
   <=
   >
   >=
   negate
   abs
   min
   max
   not
   unit panic drop unsafe-total
   i64-and i64-or i64-xor i64-shift-left i64-shift-right/logical
   i64->string string->i64 u8->i32 i32->u8 i32->i64 i64->i32 digit-value
   Option Some None Result Ok Err Never absurd Pair
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
   vector vector-set! vector-copy vector-copy!
   set! replace!
   )
  (import
   (except (chezscheme) define set! case map fold-left fold-right find
           char-whitespace? char-numeric? char-alphabetic?
           vector make-vector vector-length vector-ref vector-set! vector-copy vector-copy!
           vector-append vector-map vector-for-each vector->list list->vector)
   (prefix
    (only (chezscheme) make-vector vector-length vector-ref vector-set! vector-copy! list->vector)
    raw:)
   (snail stage0 forms))


  ;; ---- Forms ----

  ;; Snail Scheme's `case` compares keys with `=`, which on strings is `string=?`.
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

  (define (panic message) (error #f message))

  (define (unsafe-total work) (work))

  ;; Stage 0 has no FnOnce: the `resume` its handlers are handed cannot
  ;; resume (see (snail stage0 forms)), so dropping one releases nothing.
  (define (drop owned) (unit))

  (define (negate n) (- 0 n))

  (define (i64-and a b) (bitwise-and a b))
  (define (i64-or a b) (bitwise-ior a b))
  (define (i64-xor a b) (bitwise-xor a b))
  (define (i64-shift-left a n) (bitwise-arithmetic-shift a n))
  (define (i64-shift-right/logical a n) (bitwise-arithmetic-shift a (- 0 n)))

  (define (i64->string n) (number->string n))

  ;; Chez's integers are unbounded, so conversions between widths only
  ;; wrap where Snail Scheme's would: into a byte, or into 32 bits.
  (define (u8->i32 n) n)
  (define (i32->u8 n) (modulo n 256))
  (define (i32->i64 n) n)
  (define (i64->i32 n)
    (let ((low (modulo n 4294967296))) (if (>= low 2147483648) (- low 4294967296) low)))

  ;; The reader shares the compiled library's ASCII character classes.
  (define (char-whitespace? char) (if (memv char '(#\space #\tab #\newline #\return)) #t #f))
  (define (char-numeric? char) (and (char<=? #\0 char) (char<=? char #\9)))
  (define (char-alphabetic? char)
    (or (and (char<=? #\a char) (char<=? char #\z))
        (and (char<=? #\A char) (char<=? char #\Z))))

  ;; None unless every character belongs to a signed, 64-bit decimal integer.
  ;; Bound the magnitude as it grows: Chez must not accept bignums or its
  ;; wider Scheme number grammar at the compiler's input boundary.
  (define (string->i64 text)
    (if (= (string-length text) 0) (None)
        (let* ((first (string-ref text 0)) (negative? (char=? first #\-))
               (start (if (or negative? (char=? first #\+)) 1 0)))
          (decimal-i64 text start negative?))))

  (define (decimal-i64 text start negative?)
    (let ((limit (if negative? 9223372036854775808 9223372036854775807)))
      (let loop ((index start) (value 0))
        (if (= index (string-length text))
            (if (= index start) (None) (Some (if negative? (- value) value)))
            (let ((digit (digit-value (string-ref text index))))
              (if (not digit) (None)
                  (let ((next (+ (* value 10) digit)))
                    (if (> next limit) (None) (loop (+ index 1) next)))))))))

  (enum (Result T E)
    (Ok ((value T)))
    (Err ((error E))))

  ;; No value has type Never, so `absurd` is never called: an operation
  ;; that answers Never escapes to its handler (snail stage0 forms).
  (enum Never)

  (define (absurd never)
    (error #f "absurd: no value has type Never" never))

  (enum (Option T)
    (Some ((value T)))
    (None))

  (struct (Pair A B)
    ((first A)
     (second B)))

  ;; ---- Lists ----

  (define (Cons head tail) (cons head tail))
  (define (Nil) '())

  ;; Snail Scheme's `map` takes one list and calls `f` from left to right.
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

  (define (any? test items) (if (exists test items) #t #f))
  (define (every? test items) (if (for-all test items) #t #f))

  (define (find test items)
    (let loop ((items items))
      (cond ((null? items) (None))
            ((test (car items)) (Some (car items)))
            (else (loop (cdr items))))))

  (define (member? value items) (if (member value items) #t #f))

  (define (concatenate lists) (fold-right append '() lists))

  (define (delete-duplicates same? items)
    (reverse (fold-left (lambda (kept item)
                          (if (exists (lambda (other) (same? other item)) kept)
                              kept
                              (cons item kept)))
                        '() items)))

  (define (last items)
    (if (null? items) (None) (Some (car (reverse items)))))

  (define (assoc-ref entries key)
    (let loop ((entries entries))
      (cond ((null? entries) (None))
            ((equal? (● (car entries) first) key) (Some (● (car entries) second)))
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

  ;; Without `apply`, which would push every string onto Chez's stack.
  (define (string-concatenate texts)
    (let ((out (open-output-string)))
      (for-each (lambda (text) (put-string out text)) texts)
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

  ;; ---- Vectors ----

  ;; Native vectors have the same fixed length and shared mutable slots.
  (define (vector) (raw:make-vector 0))
  (define (make-vector size value) (raw:make-vector size value))
  (define (vector-length items) (raw:vector-length items))

  (define (vector-range items start count)
    (unless (and (<= 0 start (vector-length items))
                 (<= 0 count (- (vector-length items) start)))
      (panic "vector: index out of range")))

  (define (vector-ref items index)
    (vector-range items index 1)
    (raw:vector-ref items index))

  (define (vector-set! items index value)
    (vector-range items index 1)
    (raw:vector-set! items index value))





  (define (vector-generate count f)
    (let ((items (make-vector count #f)))
      (do ((index 0 (+ index 1))) ((= index count) items)
        (vector-set! items index (f index)))))

  (define (vector-copy! to at from start count)
    (vector-range to at count)
    (vector-range from start count)
    (raw:vector-copy! from start to at count))

  (define (subvector items start end)
    (vector-range items start (- end start))
    (vector-generate (- end start) (lambda (index) (vector-ref items (+ start index)))))

  (define (vector-copy items) (subvector items 0 (vector-length items)))

  (define (vector-set items index value)
    (let ((copy (vector-copy items))) (vector-set! copy index value) copy))

  (define (vector-append left right)
    (let ((size (vector-length left)))
      (vector-generate (+ size (vector-length right))
                       (lambda (index) (if (< index size) (vector-ref left index)
                                           (vector-ref right (- index size)))))))

  (define (vector-concatenate vectors)
    (let ((all (make-vector
                (fold-left (lambda (total items) (+ total (vector-length items))) 0 vectors) #f)))
      (fold-left (lambda (offset items)
                   (vector-copy! all offset items 0 (vector-length items))
                   (+ offset (vector-length items))) 0 vectors)
      all))

  (define (vector-map f items)
    (vector-generate (vector-length items) (lambda (index) (f (vector-ref items index)))))

  (define (vector-for-each f items)
    (let loop ((index 0))
      (when (< index (vector-length items)) (f (vector-ref items index)) (loop (+ index 1)))))

  (define (vector-fold f initial items)
    (let loop ((index 0) (result initial))
      (if (< index (vector-length items))
          (loop (+ index 1) (f result (vector-ref items index))) result)))

  (define (vector->list items)
    (let loop ((index (- (vector-length items) 1)) (result '()))
      (if (< index 0) result (loop (- index 1) (cons (vector-ref items index) result)))))

  (define (list->vector items) (raw:list->vector items))

  (define (string->vector text) (list->vector (string->list text)))
  (define (vector->string chars) (list->string (vector->list chars)))
  (define (take items count)
    (if (or (= count 0) (null? items)) '() (cons (car items) (take (cdr items) (- count 1)))))
  (define (list-drop items count)
    (if (or (= count 0) (null? items)) items (list-drop (cdr items) (- count 1))))
  (define (digit-value char)
    (if (and (char<=? #\0 char) (char<=? char #\9)) (- (char->integer char) 48) #f))

  ;; ---- Tests ----

  (define (test-base)
    (for-each
     (lambda (entry)
       (let ((actual (match (string->i64 (car entry)) ((Some value) value) ((None) #f))))
         (unless (equal? actual (cadr entry))
           (error 'string->i64 "host disagreement" entry actual))))
     '(("0" 0) ("-0" 0) ("+7" 7) ("00042" 42)
       ("9223372036854775807" 9223372036854775807)
       ("-9223372036854775808" -9223372036854775808)
       ("9223372036854775808" #f) ("-9223372036854775809" #f)
       ("99999999999999999999999999999999" #f) ("" #f) ("+" #f) ("-" #f)
       (" 1" #f) ("1 " #f) ("1/1" #f) ("#x10" #f) ("#e1" #f) ("1.0" #f)
       ("1e2" #f) ("12x" #f) ("١" #f)))
    (for-each
     (lambda (entry)
       (let* ((char (integer->char (car entry)))
              (actual (list (char-whitespace? char) (char-numeric? char) (char-alphabetic? char))))
         (unless (equal? actual (cdr entry))
           (error 'character-classes "host disagreement" entry actual))))
     '((9 #t #f #f) (10 #t #f #f) (13 #t #f #f) (32 #t #f #f)
       (11 #f #f #f) (12 #f #f #f) (47 #f #f #f) (48 #f #t #f) (57 #f #t #f)
       (58 #f #f #f) (64 #f #f #f) (65 #f #f #t) (90 #f #f #t) (91 #f #f #f)
       (96 #f #f #f) (97 #f #f #t) (122 #f #f #t) (123 #f #f #f)
       (160 #f #f #f) (233 #f #f #f) (1633 #f #f #f) (8195 #f #f #f))))
  )
