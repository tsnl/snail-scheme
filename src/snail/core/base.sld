;; The standard prelude: core forms, derived syntax, numeric classes, text,
;; the immutable collections, and cells. Reading and writing arrays and
;; cells performs `mut`.
(define-library (snail core base)
  (export
   define lambda fn if begin let define-syntax syntax-rules quote : struct enum type
   typeclass instance match ann type-convert type-test extern effect handle expose
   Any U8 I32 I64 F32 F64 Bool Char Unit String Array Vector Ref Bytes FnOnce Fn mut
   u8->i32 i32->u8
   let* letrec cond case when unless and or do
   not unit panic unsafe-total once call-once Drop drop Clone clone
   Num + - * negate abs
   Ord = < <= > >= min max
   Integral quotient remainder modulo
   Fractional / sqrt floor ceiling round truncate
   i32->i64 i64->i32 i64->f64 f64->i64 i32->f64 f64->i32 f32->f64 f64->f32 i64->f32 f32->i64
   i32->f32 f32->i32
   f32->bits bits->f32 f64->bits bits->f64
   Show show i64->string string->i64 f64->string
   Option Some None Result Ok Err Pair Pair-first Pair-second Never absurd
   List
   Cons
   Nil
   list
   null?
   length
   reverse
   append
   map
   map-indexed
   for-each
   filter
   fold-left
   fold-right
   list-ref list-tail any? every? find member? iota concatenate
   delete-duplicates take list-drop list-sort last list-index assoc-ref zip
   i32-and i32-or i32-xor i32-shift-left i32-shift-right i32-shift-right/logical
   i64-and i64-or i64-xor i64-shift-left i64-shift-right i64-shift-right/logical
   char->integer
   integer->char
   char->i32
   i32->char
   char-whitespace?
   char-numeric?
   char-alphabetic?
   digit-value
   char=? char<?
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
   make-array array-length array-ref array-set! array->vector vector->array array-copy! vector-copy!
   set! replace!
   Ref-contents
   Ref-contents-set!
   Ref-contents-replace!
   (rename Ref ref)
   (rename Ref-contents ref-get)
   (rename Ref-contents-set! ref-set!)
   (rename Ref-contents-replace! ref-replace!))
  (import
   (snail core forms)
   (snail core primitive)
   (rename (only (snail core primitive) string-append) (string-append append-two-strings)))
  (begin

    ;; ---- Derived syntax ----

    (define-syntax let*
      (syntax-rules ()
        ((_ () body ...) (let () body ...))
        ((_ ((name value) binding ...) body ...)
         (let ((name value)) (let* (binding ...) body ...)))))

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

    ;; The body's last expression is a Unit, and stays in tail position, so
    ;; a loop written with `when` runs in constant space.
    (define-syntax when
      (syntax-rules ()
        ((_ test body ...) (if test (begin body ...) (unit)))))

    (define-syntax unless
      (syntax-rules ()
        ((_ test body ...) (if test (unit) (begin body ...)))))

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

    (: abs (All (T) (requires (Num T) (Ord T) (Copy T)) (-> T T)))
    (define (abs x)
      (if (< x (- x x)) (negate x) x))

    (: min (All (T) (requires (Ord T) (Copy T)) (-> T T T)))
    (define (min a b)
      (if (< b a) b a))

    (: max (All (T) (requires (Ord T) (Copy T)) (-> T T T)))
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

    ;; A cell is the one struct with a mutable field, as OCaml's `ref` is;
    ;; every other struct is a value, and a program that changes one holds
    ;; it in a cell. The content lies in the cell: a `(Ref Counter)` is one
    ;; object whose slots are the counter's, and `(set! (::count (ref-get
    ;; r)) 1)` writes one of them. The field's operations are exported
    ;; under short names too: `ref` builds a cell, purely; `ref-get` and
    ;; `ref-set!` read and write its content whole; and `ref-replace!`
    ;; swaps in a new value and hands back the old. Being the field's own
    ;; operations, they keep its rules: the handle is unrestricted even
    ;; when the content is linear, which only a swap may move out, and a
    ;; function whose type has no `mut` may still use them on a cell it
    ;; allocates.
    (struct (Ref A)
      ((contents mut A)))

    ;; The type with no values. An operation that answers Never never
    ;; returns to its performer, so its handler is handed no `resume`, and
    ;; `absurd` lets the code after such a call have any type: a match on a
    ;; value of a type with no cases needs no clauses.
    (enum Never)

    (: absurd (All (A) (-> Never A)))
    (define (absurd never)
      (match never))

    ;; ---- Releasing ----

    ;; `drop` releases a value without using it, and performs what
    ;; releasing it does, found from its type: nothing for an unrestricted
    ;; value, a FnOnce, or data with nothing linear in it; the method of the
    ;; type's instance, which names its row in its head; and otherwise a
    ;; drop of each linear field. A definition that drops a value of a type
    ;; variable A requires (Drop e A), with `e` in its row:
    ;;
    ;;     (instance (Drop (! log) Handle)
    ;;       (define (drop handle) ...))
    (typeclass (Drop e T)
      (: drop (-> T Unit ! e)))

    ;; ---- Cloning ----

    ;; `clone` duplicates a value, the one it is handed and a copy, and
    ;; performs what copying it does, found from its type as a drop's is:
    ;; nothing for an unrestricted value, which both halves share; the
    ;; method of the type's instance; and otherwise a clone of each linear
    ;; field. A FnOnce runs once, so it has none, and a type its library
    ;; made linear has one only by an instance. A definition that clones a
    ;; value of a type variable A requires (Clone e A).
    (typeclass (Clone e T)
      (: clone (-> T (Pair T T) ! e)))

    ;; ---- Lists ----

    (enum (List T)
      (Nil)
      (Cons ((head T) (tail (List T)))))

    (define-syntax list
      (syntax-rules ()
        ((_) (Nil))
        ((_ item rest ...) (Cons item (list rest ...)))))

    (: null? (All (T) (requires (Copy T)) (-> (List T) Bool)))
    (define (null? items)
      (match items
        ((Nil) #t)
        ((Cons _ _) #f)))

    (: length (All (T) (requires (Copy T)) (-> (List T) I64)))
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

    (: filter (All (A e) (requires (Copy A)) (-> (-> A Bool ! e) (List A) (List A) ! e)))
    (define (filter keep? items)
      (reverse
       (fold-left (lambda (kept item) (if (keep? item) (Cons item kept) kept)) (Nil) items)))

    (: fold-left (All (A B e) (-> (-> B A B ! e) B (List A) B ! e)))
    (define (fold-left f initial items)
      (match items
        ((Nil) initial)
        ((Cons item rest) (fold-left f (f initial item) rest))))

    (: fold-right (All (A B e) (-> (-> A B B ! e) B (List A) B ! e)))
    (define (fold-right f initial items)
      (fold-left (lambda (result item) (f item result)) initial (reverse items)))

    (: list-tail (All (T) (requires (Copy T)) (-> (List T) I64 (List T))))
    (define (list-tail items index)
      (if (= index 0)
          items
          (match items
            ((Cons _ rest) (list-tail rest (- index 1)))
            ((Nil) (panic "list-tail: index out of range")))))

    (: list-ref (All (T) (requires (Copy T)) (-> (List T) I64 T)))
    (define (list-ref items index)
      (match (list-tail items index)
        ((Cons item _) item)
        ((Nil) (panic "list-ref: index out of range"))))

    (: any? (All (A e) (requires (Copy A)) (-> (-> A Bool ! e) (List A) Bool ! e)))
    (define (any? test items)
      (match items
        ((Nil) #f)
        ((Cons item rest) (if (test item) #t (any? test rest)))))

    (: every? (All (A e) (requires (Copy A)) (-> (-> A Bool ! e) (List A) Bool ! e)))
    (define (every? test items)
      (match items
        ((Nil) #t)
        ((Cons item rest) (if (test item) (every? test rest) #f))))

    (: find (All (A e) (requires (Copy A)) (-> (-> A Bool ! e) (List A) (Option A) ! e)))
    (define (find test items)
      (match items
        ((Nil) (None))
        ((Cons item rest) (if (test item) (Some item) (find test rest)))))

    (: member? (All (A) (requires (Ord A) (Copy A)) (-> A (List A) Bool)))
    (define (member? value items)
      (any? (lambda (item) (= item value)) items))

    ;; Keeps the first of each group of equal items.
    (: delete-duplicates
       (All (A e) (requires (Copy A)) (-> (-> A A Bool ! e) (List A) (List A) ! e)))
    (define (delete-duplicates same? items)
      (reverse (fold-left (lambda (kept item)
                            (if (any? (lambda (other) (same? other item)) kept)
                                kept
                                (Cons item kept)))
                          (Nil) items)))

    (: take (All (T) (requires (Copy T)) (-> (List T) I64 (List T))))
    (define (take items count)
      (let loop ((items items) (count count) (taken (Nil)))
        (match items
          ((Cons item rest)
           (if (= count 0) (reverse taken) (loop rest (- count 1) (Cons item taken))))
          ((Nil) (reverse taken)))))

    (: list-drop (All (T) (requires (Copy T)) (-> (List T) I64 (List T))))
    (define (list-drop items count)
      (if (= count 0)
          items
          (match items
            ((Cons _ rest) (list-drop rest (- count 1)))
            ((Nil) (Nil)))))

    ;; A stable merge sort: contiguous halves keep their order, and the
    ;; merge takes the left item first when neither precedes the other.
    ;; Comparing and splitting read the items, so their type must be Copy.
    (: list-sort (All (T) (requires (Copy T)) (-> (-> T T Bool) (List T) (List T))))
    (define (list-sort before? items)
      (let ((half (quotient (length items) 2)))
        (if (= half 0)
            items
            (merge-sorted before?
                          (list-sort before? (take items half))
                          (list-sort before? (list-drop items half))))))

    (: merge-sorted (All (T) (requires (Copy T)) (-> (-> T T Bool) (List T) (List T) (List T))))
    (define (merge-sorted before? left right)
      (match (Pair left right)
        ((Pair (Nil) _) right)
        ((Pair _ (Nil)) left)
        ((Pair (Cons a rest-a) (Cons b rest-b))
         (if (before? b a)
             (Cons b (merge-sorted before? left rest-b))
             (Cons a (merge-sorted before? rest-a right))))))

    (: last (All (T) (requires (Copy T)) (-> (List T) (Option T))))
    (define (last items)
      (match items
        ((Nil) (None))
        ((Cons item (Nil)) (Some item))
        ((Cons _ rest) (last rest))))

    (: list-index (All (A e) (requires (Copy A)) (-> (-> A Bool ! e) (List A) (Option I64) ! e)))
    (define (list-index test items)
      (let loop ((items items) (index 0))
        (match items
          ((Nil) (None))
          ((Cons item rest) (if (test item) (Some index) (loop rest (+ index 1)))))))

    ;; The value paired with the first occurrence of `key`.
    (: assoc-ref
       (All (K V) (requires (Ord K) (Copy K) (Copy V)) (-> (List (Pair K V)) K (Option V))))
    (define (assoc-ref entries key)
      (match entries
        ((Nil) (None))
        ((Cons entry rest)
         (if (= (Pair-first entry) key) (Some (Pair-second entry)) (assoc-ref rest key)))))

    ;; Pairs the items of two lists, stopping at the end of the shorter.
    (: zip (All (A B) (requires (Copy A) (Copy B)) (-> (List A) (List B) (List (Pair A B)))))
    (define (zip as bs)
      (let loop ((as as) (bs bs) (pairs (Nil)))
        (match as
          ((Nil) (reverse pairs))
          ((Cons a more-as)
           (match bs
             ((Nil) (reverse pairs))
             ((Cons b more-bs) (loop more-as more-bs (Cons (Pair a b) pairs))))))))

    (: iota (-> I64 (List I64)))
    (define (iota count)
      (let loop ((index (- count 1)) (items (Nil)))
        (if (< index 0) items (loop (- index 1) (Cons index items)))))

    ;; ---- Vectors and arrays ----

    (: vector-map
       (All (A B e) (requires (Copy A) (Copy B)) (-> (-> A B ! e) (Vector A) (Vector B) ! e)))
    (define (vector-map f items)
      (vector-generate (vector-length items) (lambda (index) (f (vector-ref items index)))))

    (: vector-for-each (All (A e) (requires (Copy A)) (-> (-> A Unit ! e) (Vector A) Unit ! e)))
    (define (vector-for-each f items)
      (let loop ((index 0))
        (when (< index (vector-length items))
          (f (vector-ref items index))
          (loop (+ index 1)))))

    (: vector-fold (All (A B e) (requires (Copy A)) (-> (-> B A B ! e) B (Vector A) B ! e)))
    (define (vector-fold f initial items)
      (let loop ((index 0) (result initial))
        (if (< index (vector-length items))
            (loop (+ index 1) (f result (vector-ref items index)))
            result)))

    (: vector->list (All (T) (requires (Copy T)) (-> (Vector T) (List T))))
    (define (vector->list items)
      (let loop ((index (- (vector-length items) 1)) (result (Nil)))
        (if (< index 0) result (loop (- index 1) (Cons (vector-ref items index) result)))))

    ;; The array is local to this call, so the conversion is total.
    (: list->vector (All (T) (requires (Copy T)) (-> (List T) (Vector T))))
    (define (list->vector items)
      (match items
        ((Nil) (vector-generate 0 (lambda (index) (panic "list->vector: empty"))))
        ((Cons first _)
         (let ((array (make-array (length items) first)))
           (fold-left (lambda (index item) (array-set! array index item) (+ index 1)) 0 items)
           (array->vector array)))))

    ;; Copies each vector once into one array of the total length, which is
    ;; local to this call. The array's initial element comes from the first
    ;; vector that has one.
    (: vector-concatenate (All (T) (requires (Copy T)) (-> (List (Vector T)) (Vector T))))
    (define (vector-concatenate vectors)
      (match (find (lambda (items) (> (vector-length items) 0)) vectors)
        ((None) (list->vector (Nil)))
        ((Some first)
         (let ((all (make-array
                     (fold-left (lambda (total items) (+ total (vector-length items))) 0 vectors)
                     (vector-ref first 0))))
           (fold-left (lambda (offset items)
                        (vector-copy! all offset items 0 (vector-length items))
                        (+ offset (vector-length items)))
                      0 vectors)
           (array->vector all)))))

    ;; ---- Characters and text ----

    (: char->integer (-> Char I64))
    (define (char->integer char)
      (i32->i64 (char->i32 char)))

    (: integer->char (-> I64 Char))
    (define (integer->char code)
      (i32->char (i64->i32 code)))

    (: char=? (-> Char Char Bool))
    (define (char=? a b)
      (= a b))

    (: char<? (-> Char Char Bool))
    (define (char<? a b)
      (< a b))

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

    ;; Copies each string once into one array of the total length. The array
    ;; is local to this call.
    (: string-concatenate (-> (List String) String))
    (define (string-concatenate texts)
      (let ((chars
             (make-array (fold-left (lambda (total text) (+ total (string-length text))) 0 texts)
                         #\space)))
        (fold-left (lambda (offset text)
                     (vector-copy! chars offset (string->vector text) 0 (string-length text))
                     (+ offset (string-length text)))
                   0 texts)
        (vector->string (array->vector chars))))

    (: string-join (-> (List String) String String))
    (define (string-join texts separator)
      (match texts
        ((Nil) "")
        ((Cons first rest)
         (string-concatenate (Cons first
                                   (fold-right
                                    (lambda (text joined) (Cons separator (Cons text joined)))
                                    (Nil)
                                    rest))))))

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
                        (loop (quotient n 10)
                              (Cons (integer->char (+ 48 (remainder n 10))) digits)))))))

    ;; An optionally signed decimal integer, or None if the text is not one
    ;; or does not fit in 64 bits. Digits accumulate negatively, since the
    ;; most negative value has no positive counterpart.
    (: string->i64 (-> String (Option I64)))
    (define (string->i64 text)
      (let* ((length (string-length text)) (negative (and (> length 0) (= (string-ref text 0) #\-)))
             (start (if (and (> length 0) (or negative (= (string-ref text 0) #\+))) 1 0)))
        (if (= start length)
            (None)
            (let loop ((index start) (value 0))
              (cond ((= index length)
                     (if negative
                         (Some value)
                         (if (= value -9223372036854775808) (None) (Some (negate value)))))
                    ((not (char-numeric? (string-ref text index))) (None))
                    ((< value -922337203685477580) (None))
                    ((> (- (* value 10) (digit-value (string-ref text index))) (* value 10)) (None))
                    (else
                     (loop (+ index 1) (- (* value 10) (digit-value (string-ref text index))))))))))

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

    ;; Copy the runtime's scratch text before returning. string-generate calls
    ;; only this private reader, so no user conversion can overwrite it.
    (extern real-text "snail.core.support" "snail:datum/real-text" (-> F64 I32))
    (extern text-character "snail.core.support" "snail:datum/text-character" (-> I32 Char))

    (: f64->string (-> F64 String))
    (define (f64->string value)
      (string-generate (i32->i64 (real-text value))
                       (lambda (index) (text-character (i64->i32 index)))))

    ))
