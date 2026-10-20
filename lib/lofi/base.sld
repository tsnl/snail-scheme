;; The standard prelude: core forms, derived syntax, numeric classes, text,
;; and the immutable collections. Mutable arrays and cells perform `mut`.
(define-library (lofi base)
  (export
   define lambda if begin let define-syntax syntax-rules quote : struct enum type
   typeclass instance match ann extern effect handle expose
   U8 I32 I64 F32 F64 Bool Char Unit String Array Vector Ref Bytes mut
   u8->i32 i32->u8
   let* letrec cond case when unless and or do
   not unit panic unsafe-total
   Num + - * negate abs
   Ord = < <= > >= min max
   Integral quotient remainder modulo
   Fractional / sqrt floor ceiling round truncate
   i32->i64 i64->i32 i64->f64 f64->i64 i32->f64 f64->i32 f32->f64 f64->f32 i64->f32 f32->i64
   i32->f32 f32->i32
   f32->bits bits->f32 f64->bits bits->f64
   Show show i64->string f64->string
   Option Some None Result Ok Err Pair Pair-first Pair-second
   List Cons Nil list null? length reverse append map map-indexed for-each filter fold-left fold-right
   list-ref list-tail any? every? find member? iota concatenate
   char->integer integer->char char->i32 i32->char char-whitespace? char-numeric? char-alphabetic? digit-value
   string string-length string-ref string-append substring string=? string<? make-string
   string->list list->string string-join string-concatenate string-generate string-index
   string->vector vector->string
   vector-length vector-ref make-vector vector-generate vector-set vector-append subvector
   vector-map vector-for-each vector-fold vector->list list->vector
   make-array array-length array-ref array-set! array->vector vector->array array-copy! vector-copy!
   ref ref-get ref-set!)
  (import
   (lofi core)
   (lofi primitive)
   (rename (only (lofi primitive) string-append) (string-append append-two-strings)))
  (begin

    ;; ---- Derived syntax ----

    (define-syntax let*
      (syntax-rules ()
        ((_ () body ...) (let () body ...))
        ((_ ((name value) binding ...) body ...) (let ((name value)) (let* (binding ...) body ...)))))

    (define-syntax letrec
      (syntax-rules ()
        ((_ ((name value) ...) body ...) (let () (define name value) ... (let () body ...)))))

    (define-syntax cond
      (syntax-rules (else)
        ((_ (else body ...)) (begin body ...))
        ((_ (test body ...) clause ...) (if test (begin body ...) (cond clause ...)))))

    ;; `case` compares with `=`; its last clause must be `else`.
    (define-syntax case
      (syntax-rules (else)
        ((_ key clause ...) (let ((value key)) (case-clauses value clause ...)))))

    (define-syntax case-clauses
      (syntax-rules (else)
        ((_ value (else body ...)) (begin body ...))
        ((_ value ((datum ...) body ...) clause ...)
         (if (or (= value datum) ...) (begin body ...) (case-clauses value clause ...)))))

    (define-syntax when
      (syntax-rules ()
        ((_ test body ...) (if test (begin body ... (unit)) (unit)))))

    (define-syntax unless
      (syntax-rules ()
        ((_ test body ...) (if test (unit) (begin body ... (unit))))))

    (define-syntax and
      (syntax-rules ()
        ((_) #t)
        ((_ test) test)
        ((_ test rest ...) (if test (and rest ...) #f))))

    (define-syntax or
      (syntax-rules ()
        ((_) #f)
        ((_ test) test)
        ((_ test rest ...) (if test #t (or rest ...)))))

    ;; `(do ((name init step) ...) (test result ...) body ...)`
    (define-syntax do
      (syntax-rules ()
        ((_ ((name init step) ...) (test result ...) body ...)
         (let loop ((name init) ...)
           (if test (begin (unit) result ...) (begin body ... (loop step ...)))))))

    ;; `string-append` takes any number of strings.
    (define-syntax string-append
      (syntax-rules ()
        ((_) "")
        ((_ text) text)
        ((_ text rest ...) (append-two-strings text (string-append rest ...)))))

    ;; `(string char ...)` builds a string from characters.
    (define-syntax string
      (syntax-rules ()
        ((_ char ...) (list->string (list char ...)))))

    (: not (-> Bool Bool))
    (define (not value)
      (if value #f #t))

    ;; ---- Numbers ----

    (typeclass (Num T)
      (: + (-> T T T))
      (: - (-> T T T))
      (: * (-> T T T))
      (: negate (-> T T)))

    (typeclass (Ord T)
      (: = (-> T T Bool))
      (: < (-> T T Bool))
      (: <= (-> T T Bool))
      (: > (-> T T Bool))
      (: >= (-> T T Bool)))

    (typeclass (Integral T)
      (: quotient (-> T T T))
      (: remainder (-> T T T))
      (: modulo (-> T T T)))

    (typeclass (Fractional T)
      (: / (-> T T T))
      (: sqrt (-> T T))
      (: floor (-> T T))
      (: ceiling (-> T T))
      (: round (-> T T))
      (: truncate (-> T T)))

    (instance (Num U8)
      (define (+ a b) (i32->u8 (i32-add (u8->i32 a) (u8->i32 b))))
      (define (- a b) (i32->u8 (i32-sub (u8->i32 a) (u8->i32 b))))
      (define (* a b) (i32->u8 (i32-mul (u8->i32 a) (u8->i32 b))))
      (define (negate a) (i32->u8 (i32-sub 0 (u8->i32 a)))))

    (instance (Ord U8)
      (define (= a b) (i32-eq (u8->i32 a) (u8->i32 b)))
      (define (< a b) (i32-lt (u8->i32 a) (u8->i32 b)))
      (define (<= a b) (i32-le (u8->i32 a) (u8->i32 b)))
      (define (> a b) (i32-gt (u8->i32 a) (u8->i32 b)))
      (define (>= a b) (i32-ge (u8->i32 a) (u8->i32 b))))

    (instance (Num I32)
      (define + i32-add)
      (define - i32-sub)
      (define * i32-mul)
      (define (negate x) (i32-sub 0 x)))

    (instance (Num I64)
      (define + i64-add)
      (define - i64-sub)
      (define * i64-mul)
      (define (negate x) (i64-sub 0 x)))

    (instance (Num F32)
      (define + f32-add)
      (define - f32-sub)
      (define * f32-mul)
      (define negate f32-negate))

    (instance (Num F64)
      (define + f64-add)
      (define - f64-sub)
      (define * f64-mul)
      (define negate f64-negate))

    (instance (Ord I32)
      (define = i32-eq)
      (define < i32-lt)
      (define <= i32-le)
      (define > i32-gt)
      (define >= i32-ge))

    (instance (Ord I64)
      (define = i64-eq)
      (define < i64-lt)
      (define <= i64-le)
      (define > i64-gt)
      (define >= i64-ge))

    (instance (Ord F32)
      (define = f32-eq)
      (define < f32-lt)
      (define <= f32-le)
      (define > f32-gt)
      (define >= f32-ge))

    (instance (Ord F64)
      (define = f64-eq)
      (define < f64-lt)
      (define <= f64-le)
      (define > f64-gt)
      (define >= f64-ge))

    (instance (Ord Char)
      (define (= a b) (i32-eq (char->i32 a) (char->i32 b)))
      (define (< a b) (i32-lt (char->i32 a) (char->i32 b)))
      (define (<= a b) (i32-le (char->i32 a) (char->i32 b)))
      (define (> a b) (i32-gt (char->i32 a) (char->i32 b)))
      (define (>= a b) (i32-ge (char->i32 a) (char->i32 b))))

    (instance (Ord Bool)
      (define (= a b) (i32-eq (bool->i32 a) (bool->i32 b)))
      (define (< a b) (i32-lt (bool->i32 a) (bool->i32 b)))
      (define (<= a b) (i32-le (bool->i32 a) (bool->i32 b)))
      (define (> a b) (i32-gt (bool->i32 a) (bool->i32 b)))
      (define (>= a b) (i32-ge (bool->i32 a) (bool->i32 b))))

    (instance (Ord String)
      (define = string=?)
      (define (< a b) (i32-lt (string-compare a b) 0))
      (define (<= a b) (i32-le (string-compare a b) 0))
      (define (> a b) (i32-gt (string-compare a b) 0))
      (define (>= a b) (i32-ge (string-compare a b) 0)))

    (instance (Integral I32)
      (define quotient i32-quotient)
      (define remainder i32-remainder)
      (define (modulo a b)
        (let ((r (i32-remainder a b)))
          (if (and (not (i32-eq r 0)) (not (= (i32-lt r 0) (i32-lt b 0)))) (i32-add r b) r))))

    (instance (Integral I64)
      (define quotient i64-quotient)
      (define remainder i64-remainder)
      (define (modulo a b)
        (let ((r (i64-remainder a b)))
          (if (and (not (i64-eq r 0)) (not (= (i64-lt r 0) (i64-lt b 0)))) (i64-add r b) r))))

    (instance (Fractional F32)
      (define / f32-div)
      (define sqrt f32-sqrt)
      (define floor f32-floor)
      (define ceiling f32-ceiling)
      (define round f32-round)
      (define truncate f32-truncate))

    (instance (Fractional F64)
      (define / f64-div)
      (define sqrt f64-sqrt)
      (define floor f64-floor)
      (define ceiling f64-ceiling)
      (define round f64-round)
      (define truncate f64-truncate))

    (: abs (All (T) (requires (Num T) (Ord T)) (-> T T)))
    (define (abs x)
      (if (< x (- x x)) (negate x) x))

    (: min (All (T) (requires (Ord T)) (-> T T T)))
    (define (min a b)
      (if (< b a) b a))

    (: max (All (T) (requires (Ord T)) (-> T T T)))
    (define (max a b)
      (if (< a b) b a))

    ;; Bytes are packed one per array slot.
    (type Bytes (Vector U8))

    ;; ---- Common data ----

    (enum (Option T)
      (Some ((value T)))
      (None))

    (enum (Result T E)
      (Ok ((value T)))
      (Err ((error E))))

    (struct (Pair A B)
      ((first A)
       (second B)))

    ;; ---- Lists ----

    (enum (List T)
      (Nil)
      (Cons ((head T) (tail (List T)))))

    (define-syntax list
      (syntax-rules ()
        ((_) (Nil))
        ((_ item rest ...) (Cons item (list rest ...)))))

    (: null? (All (T) (-> (List T) Bool)))
    (define (null? items)
      (match items
        ((Nil) #t)
        ((Cons _ _) #f)))

    (: length (All (T) (-> (List T) I64)))
    (define (length items)
      (fold-left (lambda (count item) (+ count 1)) 0 items))

    (: reverse (All (T) (-> (List T) (List T))))
    (define (reverse items)
      (fold-left (lambda (reversed item) (Cons item reversed)) (Nil) items))

    (: append (All (T) (-> (List T) (List T) (List T))))
    (define (append front back)
      (fold-right Cons back front))

    (: concatenate (All (T) (-> (List (List T)) (List T))))
    (define (concatenate lists)
      (fold-right append (Nil) lists))

    (: map (All (A B e) (-> (-> A B ! e) (List A) (List B) ! e)))
    (define (map f items)
      (reverse (fold-left (lambda (mapped item) (Cons (f item) mapped)) (Nil) items)))

    (: map-indexed (All (A B e) (-> (-> I64 A B ! e) (List A) (List B) ! e)))
    (define (map-indexed f items)
      (let loop ((items items) (index 0) (mapped (Nil)))
        (match items
          ((Nil) (reverse mapped))
          ((Cons item rest) (loop rest (+ index 1) (Cons (f index item) mapped))))))

    (: for-each (All (A e) (-> (-> A Unit ! e) (List A) Unit ! e)))
    (define (for-each f items)
      (match items
        ((Nil) (unit))
        ((Cons item rest) (f item) (for-each f rest))))

    (: filter (All (A e) (-> (-> A Bool ! e) (List A) (List A) ! e)))
    (define (filter keep? items)
      (reverse (fold-left (lambda (kept item) (if (keep? item) (Cons item kept) kept)) (Nil) items)))

    (: fold-left (All (A B e) (-> (-> B A B ! e) B (List A) B ! e)))
    (define (fold-left f initial items)
      (match items
        ((Nil) initial)
        ((Cons item rest) (fold-left f (f initial item) rest))))

    (: fold-right (All (A B e) (-> (-> A B B ! e) B (List A) B ! e)))
    (define (fold-right f initial items)
      (fold-left (lambda (result item) (f item result)) initial (reverse items)))

    (: list-tail (All (T) (-> (List T) I64 (List T))))
    (define (list-tail items index)
      (if (= index 0)
          items
          (match items
            ((Cons _ rest) (list-tail rest (- index 1)))
            ((Nil) (panic "list-tail: index out of range")))))

    (: list-ref (All (T) (-> (List T) I64 T)))
    (define (list-ref items index)
      (match (list-tail items index)
        ((Cons item _) item)
        ((Nil) (panic "list-ref: index out of range"))))

    (: any? (All (A e) (-> (-> A Bool ! e) (List A) Bool ! e)))
    (define (any? test items)
      (match items
        ((Nil) #f)
        ((Cons item rest) (if (test item) #t (any? test rest)))))

    (: every? (All (A e) (-> (-> A Bool ! e) (List A) Bool ! e)))
    (define (every? test items)
      (match items
        ((Nil) #t)
        ((Cons item rest) (if (test item) (every? test rest) #f))))

    (: find (All (A e) (-> (-> A Bool ! e) (List A) (Option A) ! e)))
    (define (find test items)
      (match items
        ((Nil) (None))
        ((Cons item rest) (if (test item) (Some item) (find test rest)))))

    (: member? (All (A) (requires (Ord A)) (-> A (List A) Bool)))
    (define (member? value items)
      (any? (lambda (item) (= item value)) items))

    (: iota (-> I64 (List I64)))
    (define (iota count)
      (let loop ((index (- count 1)) (items (Nil)))
        (if (< index 0) items (loop (- index 1) (Cons index items)))))

    ;; ---- Vectors and arrays ----

    (: vector-map (All (A B e) (-> (-> A B ! e) (Vector A) (Vector B) ! e)))
    (define (vector-map f items)
      (vector-generate (vector-length items) (lambda (index) (f (vector-ref items index)))))

    (: vector-for-each (All (A e) (-> (-> A Unit ! e) (Vector A) Unit ! e)))
    (define (vector-for-each f items)
      (let loop ((index 0))
        (when (< index (vector-length items))
          (f (vector-ref items index))
          (loop (+ index 1)))))

    (: vector-fold (All (A B e) (-> (-> B A B ! e) B (Vector A) B ! e)))
    (define (vector-fold f initial items)
      (let loop ((index 0) (result initial))
        (if (< index (vector-length items))
            (loop (+ index 1) (f result (vector-ref items index)))
            result)))

    (: vector->list (All (T) (-> (Vector T) (List T))))
    (define (vector->list items)
      (let loop ((index (- (vector-length items) 1)) (result (Nil)))
        (if (< index 0) result (loop (- index 1) (Cons (vector-ref items index) result)))))

    ;; The array is local to this call, so the conversion is total.
    (: list->vector (All (T) (-> (List T) (Vector T))))
    (define (list->vector items)
      (match items
        ((Nil) (vector-generate 0 (lambda (index) (panic "list->vector: empty"))))
        ((Cons first _)
         (unsafe-total
          (lambda ()
            (let ((array (make-array (length items) first)))
              (fold-left (lambda (index item) (array-set! array index item) (+ index 1)) 0 items)
              (array->vector array)))))))

    ;; ---- Characters and text ----

    (: char->integer (-> Char I64))
    (define (char->integer char)
      (i32->i64 (char->i32 char)))

    (: integer->char (-> I64 Char))
    (define (integer->char code)
      (i32->char (i64->i32 code)))

    (: char-whitespace? (-> Char Bool))
    (define (char-whitespace? char)
      (or (= char #\space) (= char #\tab) (= char #\newline) (= char #\return)))

    (: char-numeric? (-> Char Bool))
    (define (char-numeric? char)
      (and (<= #\0 char) (<= char #\9)))

    (: char-alphabetic? (-> Char Bool))
    (define (char-alphabetic? char)
      (or (and (<= #\a char) (<= char #\z)) (and (<= #\A char) (<= char #\Z))))

    (: digit-value (-> Char I64))
    (define (digit-value char)
      (- (char->integer char) 48))

    (: string<? (-> String String Bool))
    (define (string<? a b)
      (< a b))

    (: string->list (-> String (List Char)))
    (define (string->list text)
      (let loop ((index (- (string-length text) 1)) (chars (Nil)))
        (if (< index 0) chars (loop (- index 1) (Cons (string-ref text index) chars)))))

    (: list->string (-> (List Char) String))
    (define (list->string chars)
      (vector->string (list->vector chars)))

    ;; Copies each string once into one array of the total length.
    (: string-concatenate (-> (List String) String))
    (define (string-concatenate texts)
      (unsafe-total
       (lambda ()
         (let ((chars (make-array (fold-left (lambda (total text) (+ total (string-length text))) 0 texts) #\space)))
           (fold-left (lambda (offset text)
                        (vector-copy! chars offset (string->vector text) 0 (string-length text))
                        (+ offset (string-length text)))
                      0 texts)
           (vector->string (array->vector chars))))))

    (: string-join (-> (List String) String String))
    (define (string-join texts separator)
      (match texts
        ((Nil) "")
        ((Cons first rest)
         (string-concatenate (Cons first (fold-right (lambda (text joined) (Cons separator (Cons text joined))) (Nil) rest))))))

    (: string-index (-> String Char (Option I64)))
    (define (string-index text char)
      (let loop ((index 0))
        (cond ((= index (string-length text)) (None))
              ((= (string-ref text index) char) (Some index))
              (else (loop (+ index 1))))))

    ;; ---- Showing values ----

    (typeclass (Show T)
      (: show (-> T String)))

    (: i64->string (-> I64 String))
    (define (i64->string n)
      (cond ((= n 0) "0")
            ((< n 0) (if (= n -9223372036854775808)
                         "-9223372036854775808"
                         (string-append "-" (i64->string (negate n)))))
            (else (let loop ((n n) (digits (Nil)))
                    (if (= n 0)
                        (list->string digits)
                        (loop (quotient n 10) (Cons (integer->char (+ 48 (remainder n 10))) digits)))))))

    (instance (Show I64)
      (define show i64->string))

    (instance (Show U8)
      (define (show n) (i64->string (i32->i64 (u8->i32 n)))))

    (instance (Show I32)
      (define (show n) (i64->string (i32->i64 n))))

    (instance (Show Bool)
      (define (show value) (if value "#t" "#f")))

    (instance (Show Char)
      (define (show char) (make-string 1 char)))

    (instance (Show String)
      (define (show text) text))

    (instance (Show Unit)
      (define (show value) "()"))

    (instance (Show (List T))
      (requires (Show T))
      (define (show items)
        (string-append "(" (string-append (string-join (map show items) " ") ")"))))

    (instance (Show (Option T))
      (requires (Show T))
      (define (show value)
        (match value
          ((Some x) (string-append "(Some " (string-append (show x) ")")))
          ((None) "(None)"))))

    (instance (Show F64)
      (define show f64->string))

    (instance (Show F32)
      (define (show value) (f64->string (f32->f64 value))))

    ;; The runtime formats floats; the returned handle owns the text until
    ;; it is closed.
    (extern real-text "snail.library" "snail:datum/real-text" (-> F64 I32))
    (extern text-length "snail.library" "snail:datum/token-text-length" (-> I32 I32))
    (extern text-character "snail.library" "snail:datum/token-text-character" (-> I32 I32 Char))
    (extern text-close "snail.library" "snail:datum/token-close" (-> I32 Unit))

    (: f64->string (-> F64 String))
    (define (f64->string value)
      (let* ((handle (real-text value))
             (text (string-generate (i32->i64 (text-length handle))
                                    (lambda (index) (text-character handle (i64->i32 index))))))
        (text-close handle)
        text))

    ))
