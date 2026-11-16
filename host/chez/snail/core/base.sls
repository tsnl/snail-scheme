;; The compiler's standard-library boundary on Chez. Records use the same
;; mutable reference semantics as compiled code; host pairs represent Lists.
(library (snail core base)
  (export
   ● test-base
   define lambda if begin let let* letrec cond case when unless and or do
   define-syntax syntax-rules quote else => _ ...
   type ann record new enum match effect handle
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
   unit panic unsafe-total cache lru-cache
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
   string->array array->string
   array-length
   array-ref
   make-array
   array-generate
   array-set
   array-append
   array-concatenate
   subarray
   array-map array-for-each array-fold array->list list->array
   array array-set! array-copy array-copy!
   constant-array constant-array-length constant-array-ref constant-array->array
   set!
   )
  (import
   (except (chezscheme) define lambda set! case map fold-left fold-right find
           char-whitespace? char-numeric? char-alphabetic?)
   (snail stage0 forms))


  ;; ---- Forms ----

  ;; `snail-scheme`'s `case` compares keys with `=`, which on strings is `string=?`.
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

  (define (negate n) (- 0 n))

  (define (i64-and a b) (bitwise-and a b))
  (define (i64-or a b) (bitwise-ior a b))
  (define (i64-xor a b) (bitwise-xor a b))
  (define (i64-shift-left a n) (bitwise-arithmetic-shift a n))
  (define (i64-shift-right/logical a n) (bitwise-arithmetic-shift a (- 0 n)))

  (define (i64->string n) (number->string n))

  ;; Chez's integers are unbounded, so conversions between widths only
  ;; wrap where `snail-scheme`'s would: into a byte, or into 32 bits.
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

  (record (Pair A B)
    ((first A)
     (second B)))

  ;; ---- Lists ----

  (define (Cons head tail) (cons head tail))
  (define (Nil) '())

  ;; `snail-scheme`'s `map` takes one list and calls `f` from left to right.
  (define (map f items)
    (let loop ((items items) (out '()))
      (if (null? items) (reverse out) (loop (cdr items) (cons (f (car items)) out)))))

  (define (zip as bs)
    (let loop ((as as) (bs bs) (out '()))
      (if (or (null? as) (null? bs))
          (reverse out)
          (loop (cdr as) (cdr bs) (cons (new Pair (first (car as)) (second (car bs))) out)))))

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

  ;; ---- Arrays ----

  ;; Chez vectors have the same fixed length and shared mutable slots.
  (define (array) (make-vector 0))
  (define (make-array size value) (make-vector size value))
  (define (array-length items) (vector-length items))

  (define (array-range items start count)
    (unless (and (<= 0 start (array-length items))
                 (<= 0 count (- (array-length items) start)))
      (panic "array: index out of range")))

  (define (array-ref items index)
    (array-range items index 1)
    (vector-ref items index))

  (define (array-set! items index value)
    (array-range items index 1)
    (vector-set! items index value))





  (define (array-generate count f)
    (let ((items (make-array count #f)))
      (do ((index 0 (+ index 1))) ((= index count) items)
        (array-set! items index (f index)))))

  (define (array-copy! to at from start count)
    (array-range to at count)
    (array-range from start count)
    (vector-copy! from start to at count))

  (define (subarray items start end)
    (array-range items start (- end start))
    (array-generate (- end start) (lambda (index) (array-ref items (+ start index)))))

  (define (array-copy items) (subarray items 0 (array-length items)))

  (define (array-set items index value)
    (let ((copy (array-copy items))) (array-set! copy index value) copy))

  (define (array-append left right)
    (let ((size (array-length left)))
      (array-generate (+ size (array-length right))
                      (lambda (index) (if (< index size) (array-ref left index)
                                          (array-ref right (- index size)))))))

  (define (array-concatenate arrays)
    (let ((all (make-array
                (fold-left (lambda (total items) (+ total (array-length items))) 0 arrays) #f)))
      (fold-left (lambda (offset items)
                   (array-copy! all offset items 0 (array-length items))
                   (+ offset (array-length items))) 0 arrays)
      all))

  (define (array-map f items)
    (array-generate (array-length items) (lambda (index) (f (array-ref items index)))))

  (define (array-for-each f items)
    (let loop ((index 0))
      (when (< index (array-length items)) (f (array-ref items index)) (loop (+ index 1)))))

  (define (array-fold f initial items)
    (let loop ((index 0) (result initial))
      (if (< index (array-length items))
          (loop (+ index 1) (f result (array-ref items index))) result)))

  (define (array->list items)
    (let loop ((index (- (array-length items) 1)) (result '()))
      (if (< index 0) result (loop (- index 1) (cons (array-ref items index) result)))))

  (define (list->array items) (list->vector items))

  ;; A constant array is an array nothing writes; the type, erased here,
  ;; is what forbids writing it. A quoted array is made once, as code
  ;; loads, so every evaluation shares it, as compiled code does.
  (define-syntax constant-array
    (syntax-rules () ((_ type (value ...)) (quote #(value ...)))))
  (define (constant-array-length items) (array-length items))
  (define (constant-array-ref items index) (array-ref items index))
  (define (constant-array->array items) (array-copy items))

  (define (string->array text) (list->array (string->list text)))
  (define (array->string chars) (list->string (array->list chars)))
  (define (take items count)
    (if (or (= count 0) (null? items)) '() (cons (car items) (take (cdr items) (- count 1)))))
  (define (list-drop items count)
    (if (or (= count 0) (null? items)) items (list-drop (cdr items) (- count 1))))
  (define (digit-value char)
    (if (and (char<=? #\0 char) (char<=? char #\9)) (- (char->integer char) 48) #f))

  ;; ---- Memoized closures ----

  ;; Keys are argument tuples. Strings compare by content, floats by bits,
  ;; and other heap values by identity, as in the WasmGC implementation.
  (define (cache-float-bits value)
    (let ((bytes (make-bytevector 8)))
      (bytevector-ieee-double-native-set! bytes 0 value)
      (bytevector-u64-native-ref bytes 0)))

  (define (cache-key=? a b)
    (cond ((and (string? a) (string? b)) (string=? a b))
          ((and (flonum? a) (flonum? b)) (= (cache-float-bits a) (cache-float-bits b)))
          ((and (integer? a) (exact? a) (integer? b) (exact? b)) (= a b))
          (else (eq? a b))))

  (define (cache-arguments=? as bs)
    (if (null? as) (null? bs)
        (and (pair? bs) (cache-key=? (car as) (car bs))
             (cache-arguments=? (cdr as) (cdr bs)))))

  (define (cache-mix hash value)
    (bitwise-and (* (bitwise-xor hash value) 1099511628211) #xffffffffffffffff))

  (define (cache-key-hash value)
    (cond ((string? value)
           (fold-left (lambda (hash char) (cache-mix hash (char->integer char)))
                      #xcbf29ce484222325 (string->list value)))
          ((flonum? value) (cache-float-bits value))
          ((and (integer? value) (exact? value)) value)
          ((char? value) (char->integer value))
          ((boolean? value) (if value 1 0))
          (else 0)))

  (define (cache-argument-hash arguments)
    (fold-left (lambda (hash key) (cache-mix hash (cache-key-hash key)))
               #xcbf29ce484222325 arguments))

  ;; The map and recency list belong to this invocation of the factory.
  ;; Entries hold argument keys, result, newer and older.
  (define (cache-wrapper capacity f)
    (let ((entries (make-hashtable cache-argument-hash cache-arguments=?))
          (head #f) (tail #f))
      (define (touch entry)
        (unless (or (= capacity 0) (eq? entry head))
          (let ((newer (vector-ref entry 2)) (older (vector-ref entry 3)))
            (when newer (vector-set! newer 3 older))
            (if older (vector-set! older 2 newer) (set! tail newer))
            (vector-set! entry 2 #f)
            (vector-set! entry 3 head)
            (when head (vector-set! head 2 entry))
            (set! head entry))))
      (define (publish arguments value)
        ;; User code can reenter: find again after it returns.
        (let ((found (hashtable-ref entries arguments #f)))
          (if found (begin (vector-set! found 1 value) (touch found))
              (let ((entry (list->vector (list arguments value #f head))))
                (hashtable-set! entries arguments entry)
                (if head (vector-set! head 2 entry) (set! tail entry))
                (set! head entry)
                (when (and (> capacity 0) (> (hashtable-size entries) capacity))
                  (hashtable-delete! entries (vector-ref tail 0))
                  (set! tail (vector-ref tail 2))
                  (if tail (vector-set! tail 3 #f) (set! head #f)))))))
      (lambda arguments
        (let ((entry (hashtable-ref entries arguments #f)))
          (if entry (begin (touch entry) (vector-ref entry 1))
              (let ((value (apply f arguments))) (publish arguments value) value))))))

  (define (cache f) (cache-wrapper 0 f))
  (define (lru-cache capacity f)
    (cond ((< capacity 0) (panic "lru-cache capacity must be nonnegative"))
          ((= capacity 0) f)
          (else (cache-wrapper capacity f))))

  ;; ---- Tests ----

  (define (test-cache)
    (let* ((calls 0)
           (work (lambda args (set! calls (+ calls 1)) (list->vector (list calls))))
           (memo (cache work)) (alias memo) (other (cache work)))
      (let ((first (memo 1 "a")))
        (unless (eq? first (alias 1 (make-string 1 #\a))) (error 'cache "string key miss"))
        (when (eq? first (other 1 "a")) (error 'cache "separate wrappers shared state")))
      (let ((key (make-vector 1 0)))
        (let ((first (memo key)))
          (vector-set! key 0 1)
          (unless (eq? first (memo key)) (error 'cache "identity key changed"))))
      (unless (eq? (memo (None)) (memo (None))) (error 'cache "enum singleton mismatch"))
      (when (eq? (memo 0.0) (memo -0.0)) (error 'cache "lost signed zero"))
      (let ((lru (lru-cache 2 work)))
        (let ((one (lru 1)) (two (lru 2)))
          (unless (eq? one (lru 1)) (error 'lru-cache "lost entry"))
          (lru 3)
          (when (eq? two (lru 2)) (error 'lru-cache "wrong eviction order"))))
      (let* ((zero (lru-cache 0 work)) (first (zero)))
        (when (eq? first (zero)) (error 'lru-cache "capacity zero retained an entry"))))
    (let ((memo #f) (entered? #f))
      (set! memo (cache (lambda (key)
                          (if entered? key
                              (begin (set! entered? #t) (+ (memo key) 1))))))
      (unless (= (memo 10) 11) (error 'cache "reentrant result"))
      (unless (= (memo 10) 11) (error 'cache "last completion must win"))))

  (define (test-base)
    (test-cache)
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
