;; The standard prelude: core forms, derived syntax, numeric classes, text,
;; collections and mutable heap objects. Writes perform `mut`; reads are pure.
(define-library (snail core base)
  (export
   ●
   define lambda if begin let define-syntax syntax-rules quote declare record new enum type
   typeclass
   instance
   match
   ann
   downcast
   constant-array
   extern
   effect
   handle
   expose
   Any U8 I32 I64 F32 F64 Bool Char Unit String Array ConstantArray Bytes Fn mut
   u8->i32 i32->u8
   let* letrec cond case when unless and or do
   not unit panic unsafe-total
   cache lru-cache
   Num + - * negate abs
   Ord = < <= > >= min max
   Integral quotient remainder modulo
   Fractional / sqrt floor ceiling round truncate
   i32->i64 i64->i32 i64->f64 f64->i64 i32->f64 f64->i32 f32->f64 f64->f32 i64->f32 f32->i64
   i32->f32 f32->i32
   f32->bits bits->f32 f64->bits bits->f64
   Show show i64->string string->i64 f64->string
   Repr repr derive-repr-record derive-repr-enum
   Option Some None Result Ok Err Pair Never absurd
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
   string->array array->string
   array-length
   array-ref
   constant-array-length
   constant-array-ref
   constant-array->array
   make-array
   array-generate
   array-set
   array-append
   array-concatenate
   subarray
   array-map array-for-each array-fold array->list list->array
   array array-set! array-copy array-copy!
   set!)
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

    (define (not (value Bool)) (→ Bool)
      (if value #f #t))

    ;; ---- Numbers ----

    (typeclass (Num T)
      (declare (+ (left T) (right T)) (→ T))
      (declare (- (left T) (right T)) (→ T))
      (declare (* (left T) (right T)) (→ T))
      (declare (negate (value T)) (→ T)))

    (typeclass (Ord T)
      (declare (= (left T) (right T)) (→ Bool))
      (declare (< (left T) (right T)) (→ Bool))
      (declare (<= (left T) (right T)) (→ Bool))
      (declare (> (left T) (right T)) (→ Bool))
      (declare (>= (left T) (right T)) (→ Bool)))

    (typeclass (Integral T)
      (declare (quotient (numerator T) (denominator T)) (→ T))
      (declare (remainder (numerator T) (denominator T)) (→ T))
      (declare (modulo (numerator T) (denominator T)) (→ T)))

    (typeclass (Fractional T)
      (declare (/ (left T) (right T)) (→ T))
      (declare (sqrt (value T)) (→ T))
      (declare (floor (value T)) (→ T))
      (declare (ceiling (value T)) (→ T))
      (declare (round (value T)) (→ T))
      (declare (truncate (value T)) (→ T)))

    (instance (Num U8)
      (define (+ (a U8) (b U8)) (→ U8)
        (i32->u8 (i32-add (u8->i32 a) (u8->i32 b))))
      (define (- (a U8) (b U8)) (→ U8)
        (i32->u8 (i32-sub (u8->i32 a) (u8->i32 b))))
      (define (* (a U8) (b U8)) (→ U8)
        (i32->u8 (i32-mul (u8->i32 a) (u8->i32 b))))
      (define (negate (a U8)) (→ U8)
        (i32->u8 (i32-sub 0 (u8->i32 a)))))

    (instance (Ord U8)
      (define (= (a U8) (b U8)) (→ Bool)
        (i32-eq (u8->i32 a) (u8->i32 b)))
      (define (< (a U8) (b U8)) (→ Bool)
        (i32-lt (u8->i32 a) (u8->i32 b)))
      (define (<= (a U8) (b U8)) (→ Bool)
        (i32-le (u8->i32 a) (u8->i32 b)))
      (define (> (a U8) (b U8)) (→ Bool)
        (i32-gt (u8->i32 a) (u8->i32 b)))
      (define (>= (a U8) (b U8)) (→ Bool)
        (i32-ge (u8->i32 a) (u8->i32 b))))

    (instance (Num I32)
      (define (+ (left I32) (right I32)) (→ I32)
        (i32-add left right))
      (define (- (left I32) (right I32)) (→ I32)
        (i32-sub left right))
      (define (* (left I32) (right I32)) (→ I32)
        (i32-mul left right))
      (define (negate (x I32)) (→ I32)
        (i32-sub 0 x)))

    (instance (Num I64)
      (define (+ (left I64) (right I64)) (→ I64)
        (i64-add left right))
      (define (- (left I64) (right I64)) (→ I64)
        (i64-sub left right))
      (define (* (left I64) (right I64)) (→ I64)
        (i64-mul left right))
      (define (negate (x I64)) (→ I64)
        (i64-sub 0 x)))

    (instance (Num F32)
      (define (+ (left F32) (right F32)) (→ F32)
        (f32-add left right))
      (define (- (left F32) (right F32)) (→ F32)
        (f32-sub left right))
      (define (* (left F32) (right F32)) (→ F32)
        (f32-mul left right))
      (define (negate (value F32)) (→ F32)
        (f32-negate value)))

    (instance (Num F64)
      (define (+ (left F64) (right F64)) (→ F64)
        (f64-add left right))
      (define (- (left F64) (right F64)) (→ F64)
        (f64-sub left right))
      (define (* (left F64) (right F64)) (→ F64)
        (f64-mul left right))
      (define (negate (value F64)) (→ F64)
        (f64-negate value)))

    (instance (Ord I32)
      (define (= (left I32) (right I32)) (→ Bool)
        (i32-eq left right))
      (define (< (left I32) (right I32)) (→ Bool)
        (i32-lt left right))
      (define (<= (left I32) (right I32)) (→ Bool)
        (i32-le left right))
      (define (> (left I32) (right I32)) (→ Bool)
        (i32-gt left right))
      (define (>= (left I32) (right I32)) (→ Bool)
        (i32-ge left right)))

    (instance (Ord I64)
      (define (= (left I64) (right I64)) (→ Bool)
        (i64-eq left right))
      (define (< (left I64) (right I64)) (→ Bool)
        (i64-lt left right))
      (define (<= (left I64) (right I64)) (→ Bool)
        (i64-le left right))
      (define (> (left I64) (right I64)) (→ Bool)
        (i64-gt left right))
      (define (>= (left I64) (right I64)) (→ Bool)
        (i64-ge left right)))

    (instance (Ord F32)
      (define (= (left F32) (right F32)) (→ Bool)
        (f32-eq left right))
      (define (< (left F32) (right F32)) (→ Bool)
        (f32-lt left right))
      (define (<= (left F32) (right F32)) (→ Bool)
        (f32-le left right))
      (define (> (left F32) (right F32)) (→ Bool)
        (f32-gt left right))
      (define (>= (left F32) (right F32)) (→ Bool)
        (f32-ge left right)))

    (instance (Ord F64)
      (define (= (left F64) (right F64)) (→ Bool)
        (f64-eq left right))
      (define (< (left F64) (right F64)) (→ Bool)
        (f64-lt left right))
      (define (<= (left F64) (right F64)) (→ Bool)
        (f64-le left right))
      (define (> (left F64) (right F64)) (→ Bool)
        (f64-gt left right))
      (define (>= (left F64) (right F64)) (→ Bool)
        (f64-ge left right)))

    (instance (Ord Char)
      (define (= (a Char) (b Char)) (→ Bool)
        (i32-eq (char->i32 a) (char->i32 b)))
      (define (< (a Char) (b Char)) (→ Bool)
        (i32-lt (char->i32 a) (char->i32 b)))
      (define (<= (a Char) (b Char)) (→ Bool)
        (i32-le (char->i32 a) (char->i32 b)))
      (define (> (a Char) (b Char)) (→ Bool)
        (i32-gt (char->i32 a) (char->i32 b)))
      (define (>= (a Char) (b Char)) (→ Bool)
        (i32-ge (char->i32 a) (char->i32 b))))

    (instance (Ord Bool)
      (define (= (a Bool) (b Bool)) (→ Bool)
        (i32-eq (bool->i32 a) (bool->i32 b)))
      (define (< (a Bool) (b Bool)) (→ Bool)
        (i32-lt (bool->i32 a) (bool->i32 b)))
      (define (<= (a Bool) (b Bool)) (→ Bool)
        (i32-le (bool->i32 a) (bool->i32 b)))
      (define (> (a Bool) (b Bool)) (→ Bool)
        (i32-gt (bool->i32 a) (bool->i32 b)))
      (define (>= (a Bool) (b Bool)) (→ Bool)
        (i32-ge (bool->i32 a) (bool->i32 b))))

    (instance (Ord String)
      (define (= (left String) (right String)) (→ Bool)
        (string=? left right))
      (define (< (a String) (b String)) (→ Bool)
        (i32-lt (string-compare a b) 0))
      (define (<= (a String) (b String)) (→ Bool)
        (i32-le (string-compare a b) 0))
      (define (> (a String) (b String)) (→ Bool)
        (i32-gt (string-compare a b) 0))
      (define (>= (a String) (b String)) (→ Bool)
        (i32-ge (string-compare a b) 0)))

    (instance (Integral I32)
      (define (quotient (left I32) (right I32)) (→ I32)
        (i32-quotient left right))
      (define (remainder (left I32) (right I32)) (→ I32)
        (i32-remainder left right))
      (define (modulo (a I32) (b I32)) (→ I32)
        (let ((r (i32-remainder a b)))
          (if (and (not (i32-eq r 0)) (not (= (i32-lt r 0) (i32-lt b 0))))
              (i32-add r b)
              r))))

    (instance (Integral I64)
      (define (quotient (left I64) (right I64)) (→ I64)
        (i64-quotient left right))
      (define (remainder (left I64) (right I64)) (→ I64)
        (i64-remainder left right))
      (define (modulo (a I64) (b I64)) (→ I64)
        (let ((r (i64-remainder a b)))
          (if (and (not (i64-eq r 0)) (not (= (i64-lt r 0) (i64-lt b 0))))
              (i64-add r b)
              r))))

    (instance (Fractional F32)
      (define (/ (left F32) (right F32)) (→ F32)
        (f32-div left right))
      (define (sqrt (value F32)) (→ F32)
        (f32-sqrt value))
      (define (floor (value F32)) (→ F32)
        (f32-floor value))
      (define (ceiling (value F32)) (→ F32)
        (f32-ceiling value))
      (define (round (value F32)) (→ F32)
        (f32-round value))
      (define (truncate (value F32)) (→ F32)
        (f32-truncate value)))

    (instance (Fractional F64)
      (define (/ (left F64) (right F64)) (→ F64)
        (f64-div left right))
      (define (sqrt (value F64)) (→ F64)
        (f64-sqrt value))
      (define (floor (value F64)) (→ F64)
        (f64-floor value))
      (define (ceiling (value F64)) (→ F64)
        (f64-ceiling value))
      (define (round (value F64)) (→ F64)
        (f64-round value))
      (define (truncate (value F64)) (→ F64)
        (f64-truncate value)))

    (define (abs (x T))
      (→ T)
      (∀ (T))
      (⊨ (Num T) (Ord T))
      (if (< x (- x x)) (negate x) x))

    (define (min (a T) (b T))
      (→ T)
      (∀ (T))
      (⊨ (Ord T))
      (if (< b a) b a))

    (define (max (a T) (b T))
      (→ T)
      (∀ (T))
      (⊨ (Ord T))
      (if (< a b) b a))

    ;; Bytes are packed one per array slot.
    (type Bytes (Array U8))

    ;; ---- Common data ----

    (enum (Option T)
      (Some ((value T)))
      (None))

    (enum (Result T E)
      (Ok ((value T)))
      (Err ((error E))))

    (record (Pair A B)
      ((first A)
       (second B)))

    ;; The type with no values. An operation that answers Never never
    ;; returns to its performer, so its handler is handed no `resume`, and
    ;; `absurd` lets the code after such a call have any type: a match on a
    ;; value of a type with no cases needs no clauses.
    (enum Never)

    (define (absurd (never Never)) (→ A) (∀ (A))
      (match never))

    ;; ---- Lists ----

    (enum (List T)
      (Nil)
      (Cons ((head T) (tail (List T)))))

    (define-syntax list
      (syntax-rules ()
        ((_) (Nil))
        ((_ item rest ...) (Cons item (list rest ...)))))

    (define (null? (items (List T)))
      (→ Bool)
      (∀ (T))
      (match items
        ((Nil) #t)
        ((Cons _ _) #f)))

    (define (length (items (List T)))
      (→ I64)
      (∀ (T))
      (fold-left (lambda (count item) (+ count 1)) 0 items))

    (define (reverse (items (List T))) (→ (List T)) (∀ (T))
      (fold-left (lambda (reversed item) (Cons item reversed)) (Nil) items))

    (define (append (front (List T)) (back (List T))) (→ (List T)) (∀ (T))
      (fold-right Cons back front))

    (define (concatenate (lists (List (List T)))) (→ (List T)) (∀ (T))
      (fold-right append (Nil) lists))

    (define (map (f (Fn A → B ! e)) (items (List A)))
      (→ (List B))
      (! e)
      (∀ (A B e))
      (reverse (fold-left (lambda (mapped item) (Cons (f item) mapped)) (Nil) items)))

    (define (map-indexed (f (Fn I64 A → B ! e)) (items (List A)))
      (→ (List B))
      (! e)
      (∀ (A B e))
      (let loop ((items items) (index 0) (mapped (Nil)))
        (match items
          ((Nil) (reverse mapped))
          ((Cons item rest) (loop rest (+ index 1) (Cons (f index item) mapped))))))

    (define (for-each (f (Fn A → Unit ! e)) (items (List A)))
      (→ Unit)
      (! e)
      (∀ (A e))
      (match items
        ((Nil) (unit))
        ((Cons item rest) (f item) (for-each f rest))))

    (define (filter (keep? (Fn A → Bool ! e)) (items (List A)))
      (→ (List A))
      (! e)
      (∀ (A e))
      (reverse
       (fold-left (lambda (kept item) (if (keep? item) (Cons item kept) kept)) (Nil) items)))

    (define (fold-left (f (Fn B A → B ! e)) (initial B) (items (List A)))
      (→ B)
      (! e)
      (∀ (A B e))
      (match items
        ((Nil) initial)
        ((Cons item rest) (fold-left f (f initial item) rest))))

    (define (fold-right (f (Fn A B → B ! e)) (initial B) (items (List A)))
      (→ B)
      (! e)
      (∀ (A B e))
      (fold-left (lambda (result item) (f item result)) initial (reverse items)))

    (define (list-tail (items (List T)) (index I64))
      (→ (List T))
      (∀ (T))
      (if (= index 0)
          items
          (match items
            ((Cons _ rest) (list-tail rest (- index 1)))
            ((Nil) (panic "list-tail: index out of range")))))

    (define (list-ref (items (List T)) (index I64))
      (→ T)
      (∀ (T))
      (match (list-tail items index)
        ((Cons item _) item)
        ((Nil) (panic "list-ref: index out of range"))))

    (define (any? (test (Fn A → Bool ! e)) (items (List A)))
      (→ Bool)
      (! e)
      (∀ (A e))
      (match items
        ((Nil) #f)
        ((Cons item rest) (if (test item) #t (any? test rest)))))

    (define (every? (test (Fn A → Bool ! e)) (items (List A)))
      (→ Bool)
      (! e)
      (∀ (A e))
      (match items
        ((Nil) #t)
        ((Cons item rest) (if (test item) (every? test rest) #f))))

    (define (find (test (Fn A → Bool ! e)) (items (List A)))
      (→ (Option A))
      (! e)
      (∀ (A e))
      (match items
        ((Nil) (None))
        ((Cons item rest) (if (test item) (Some item) (find test rest)))))

    (define (member? (value A) (items (List A)))
      (→ Bool)
      (∀ (A))
      (⊨ (Ord A))
      (any? (lambda (item) (= item value)) items))

    ;; Keeps the first of each group of equal items.

    (define (delete-duplicates (same? (Fn A A → Bool ! e)) (items (List A)))
      (→ (List A))
      (! e)
      (∀ (A e))
      (reverse (fold-left (lambda (kept item)
                            (if (any? (lambda (other) (same? other item)) kept)
                                kept
                                (Cons item kept)))
                          (Nil) items)))

    (define (take (items (List T)) (count I64))
      (→ (List T))
      (∀ (T))
      (let loop ((items items) (count count) (taken (Nil)))
        (match items
          ((Cons item rest)
           (if (= count 0) (reverse taken) (loop rest (- count 1) (Cons item taken))))
          ((Nil) (reverse taken)))))

    (define (list-drop (items (List T)) (count I64))
      (→ (List T))
      (∀ (T))
      (if (= count 0)
          items
          (match items
            ((Cons _ rest) (list-drop rest (- count 1)))
            ((Nil) (Nil)))))

    ;; A stable merge sort: contiguous halves keep their order, and the
    ;; merge takes the left item first when neither precedes the other.

    (define (list-sort (before? (Fn T T → Bool ! e)) (items (List T)))
      (→ (List T))
      (! e)
      (∀ (T e))
      (let ((half (quotient (length items) 2)))
        (if (= half 0)
            items
            (merge-sorted before?
                          (list-sort before? (take items half))
                          (list-sort before? (list-drop items half))))))

    (define (merge-sorted (before? (Fn T T → Bool ! e)) (left (List T)) (right (List T)))
      (→ (List T)) (! e) (∀ (T e))
      ;; The merge is linear in the list length, but uses constant stack.
      ;; Equal elements come from the left run first, preserving stability.
      (let loop ((left left) (right right) (reversed (Nil)))
        (match (new Pair (first left) (second right))
          ((Pair (Nil) _) (fold-left (lambda (rest item) (Cons item rest)) right reversed))
          ((Pair _ (Nil)) (fold-left (lambda (rest item) (Cons item rest)) left reversed))
          ((Pair (Cons a rest-a) (Cons b rest-b))
           (if (before? b a) (loop left rest-b (Cons b reversed))
               (loop rest-a right (Cons a reversed)))))))

    (define (last (items (List T)))
      (→ (Option T))
      (∀ (T))
      (match items
        ((Nil) (None))
        ((Cons item (Nil)) (Some item))
        ((Cons _ rest) (last rest))))

    (define (list-index (test (Fn A → Bool ! e)) (items (List A)))
      (→ (Option I64))
      (! e)
      (∀ (A e))
      (let loop ((items items) (index 0))
        (match items
          ((Nil) (None))
          ((Cons item rest) (if (test item) (Some index) (loop rest (+ index 1)))))))

    ;; The value paired with the first occurrence of `key`.

    (define (assoc-ref (entries (List (Pair K V))) (key K))
      (→ (Option V))
      (∀ (K V))
      (⊨ (Ord K))
      (match entries
        ((Nil) (None))
        ((Cons entry rest)
         (if (= (● entry first) key) (Some (● entry second)) (assoc-ref rest key)))))

    ;; Pairs the items of two lists, stopping at the end of the shorter.

    (define (zip (as (List A)) (bs (List B)))
      (→ (List (Pair A B)))
      (∀ (A B))
      (let loop ((as as) (bs bs) (pairs (Nil)))
        (match as
          ((Nil) (reverse pairs))
          ((Cons a more-as)
           (match bs
             ((Nil) (reverse pairs))
             ((Cons b more-bs)
              (loop more-as more-bs (Cons (new Pair (first a) (second b)) pairs))))))))

    (define (iota (count I64)) (→ (List I64))
      (let loop ((index (- count 1)) (items (Nil)))
        (if (< index 0) items (loop (- index 1) (Cons index items)))))

    ;; ---- Arrays ----

    (define (array-map (f (Fn A → B ! e)) (items (Array A)))
      (→ (Array B))
      (! e)
      (∀ (A B e))
      (array-generate (array-length items) (lambda (index) (f (array-ref items index)))))

    (define (array-for-each (f (Fn A → Unit ! e)) (items (Array A)))
      (→ Unit)
      (! e)
      (∀ (A e))
      (let loop ((index 0))
        (when (< index (array-length items))
          (f (array-ref items index))
          (loop (+ index 1)))))

    (define (array-fold (f (Fn B A → B ! e)) (initial B) (items (Array A)))
      (→ B)
      (! e)
      (∀ (A B e))
      (let loop ((index 0) (result initial))
        (if (< index (array-length items))
            (loop (+ index 1) (f result (array-ref items index)))
            result)))

    (define (array->list (items (Array T)))
      (→ (List T))
      (∀ (T))
      (let loop ((index (- (array-length items) 1)) (result (Nil)))
        (if (< index 0) result (loop (- index 1) (Cons (array-ref items index) result)))))

    ;; Local cursors give generation a sequential input without exposing
    ;; mutable storage outside these total conversions.
    (record (ListCursor A)
      ((remaining (List A))))

    (define (list->array (items (List T)))
      (→ (Array T))
      (! e)
      (∀ (T e))
      (unsafe-total (ann (lambda () (let ((cursor (new ListCursor (remaining items))))
                                      (array-generate (length items)
                                                      (lambda (index)
                                                        (match (● cursor remaining)
                                                          ((Cons first rest)
                                                           (set! (● cursor remaining) rest)
                                                           first)
                                                          ((Nil)
                                                           (panic
                                                            "list->array: too few items")))))))
                         (Fn → (Array T) ! mut e))))

    (record (ArrayCursor A)
      ((arrays (List (Array A)))
       (offset I64)))

    (define (array-concatenate (arrays (List (Array T))))
      (→ (Array T))
      (! e)
      (∀ (T e))
      (unsafe-total (ann (lambda () (let ((cursor (new ArrayCursor (arrays arrays) (offset 0))))
                                      (array-generate
                                       (fold-left
                                        (lambda (total items) (+ total (array-length items)))
                                        0
                                        arrays)
                                       (lambda (index)
                                         (let next ()
                                           (match (● cursor arrays)
                                             ((Cons items rest)
                                              (let ((offset (● cursor offset)))
                                                (if (< offset (array-length items))
                                                    (begin
                                                      (set! (● cursor offset) (+ offset 1))
                                                      (array-ref items offset))
                                                    (begin
                                                      (set! (● cursor arrays) rest)
                                                      (set! (● cursor offset) 0)
                                                      (next)))))
                                             ((Nil)
                                              (panic "array-concatenate: too few elements"))))))))
                         (Fn → (Array T) ! mut e))))

    ;; ---- Characters and text ----

    (define (char->integer (char Char)) (→ I64)
      (i32->i64 (char->i32 char)))

    (define (integer->char (code I64)) (→ Char)
      (i32->char (i64->i32 code)))

    (define (char=? (a Char) (b Char)) (→ Bool)
      (= a b))

    (define (char<? (a Char) (b Char)) (→ Bool)
      (< a b))

    (define (char-whitespace? (char Char)) (→ Bool)
      (or (= char #\space) (= char #\tab) (= char #\newline) (= char #\return)))

    (define (char-numeric? (char Char)) (→ Bool)
      (and (<= #\0 char) (<= char #\9)))

    (define (char-alphabetic? (char Char)) (→ Bool)
      (or (and (<= #\a char) (<= char #\z)) (and (<= #\A char) (<= char #\Z))))

    (define (digit-value (char Char)) (→ I64)
      (- (char->integer char) 48))

    (define (string<? (a String) (b String)) (→ Bool)
      (< a b))

    (define (string->list (text String)) (→ (List Char))
      (let loop ((index (- (string-length text) 1)) (chars (Nil)))
        (if (< index 0) chars (loop (- index 1) (Cons (string-ref text index) chars)))))

    (define (list->string (chars (List Char))) (→ String)
      (array->string (list->array chars)))

    ;; Copies each string once into one array of the total length. The array
    ;; is local to this call.

    (define (string-concatenate (texts (List String))) (→ String)
      (unsafe-total (lambda () (let ((chars
                                      (make-array (fold-left (lambda (total text)
                                                               (+ total (string-length text)))
                                                             0
                                                             texts)
                                                  #\space)))
                                 (fold-left (lambda (offset text)
                                              (array-copy! chars
                                                           offset
                                                           (string->array text)
                                                           0
                                                           (string-length text))
                                              (+ offset (string-length text)))
                                            0 texts)
                                 (array->string chars)))))

    (define (string-join (texts (List String)) (separator String)) (→ String)
      (match texts
        ((Nil) "")
        ((Cons first rest)
         (string-concatenate (Cons first
                                   (fold-right
                                    (lambda (text joined) (Cons separator (Cons text joined)))
                                    (Nil)
                                    rest))))))

    (define (string-index (text String) (char Char)) (→ (Option I64))
      (let loop ((index 0))
        (cond ((= index (string-length text)) (None))
              ((= (string-ref text index) char) (Some index))
              (else (loop (+ index 1))))))

    ;; ---- Showing values ----

    (typeclass (Show T)
      (declare (show (value T)) (→ String)))

    (define (i64->string (n I64)) (→ String)
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

    (define (string->i64 (text String)) (→ (Option I64))
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
      (define (show (value I64)) (→ String)
        (i64->string value)))

    (instance (Show U8)
      (define (show (n U8)) (→ String)
        (i64->string (i32->i64 (u8->i32 n)))))

    (instance (Show I32)
      (define (show (n I32)) (→ String)
        (i64->string (i32->i64 n))))

    (instance (Show Bool)
      (define (show (value Bool)) (→ String)
        (if value "#t" "#f")))

    (instance (Show Char)
      (define (show (char Char)) (→ String)
        (make-string 1 char)))

    (instance (Show String)
      (define (show (text String)) (→ String)
        text))

    (instance (Show Unit)
      (define (show (value Unit)) (→ String)
        "()"))

    (instance (Show F64)
      (define (show (value F64)) (→ String)
        (f64->string value)))

    (instance (Show F32)
      (define (show (value F32)) (→ String)
        (f64->string (f32->f64 value))))

    ;; ---- Printing reals ----

    ;; A double prints as the shortest decimal that reads back as it, and
    ;; the nearest such when several are as short, laid out as Rust's `{:?}`
    ;; lays it out: positionally from 1e-4 up to 1e16, with at least one
    ;; fractional digit, and in scientific notation otherwise, its exponent
    ;; signed so the text reads the same in every host ("1e+22", "5e-324").

    (define (f64->string (value F64)) (→ String)
      (cond ((not (= value value)) "+nan.0")
            ((= value (/ 1.0 0.0)) "+inf.0")
            ((= value (/ -1.0 0.0)) "-inf.0")
            (else (string-append (if (< (f64->bits value) 0) "-" "")
                                 (magnitude-text (bits->f64 (i64-and (f64->bits value)
                                                                     9223372036854775807)))))))

    (define (magnitude-text (value F64)) (→ String)
      (cond ((= value 0.0) "0.0")
            ((or (< value 1e-4) (>= value 1e16)) (scientific (shortest-digits value)))
            (else (positional (shortest-digits value)))))

    ;; 0.d1 d2 ... dn × 10^exponent, d1 nonzero.
    (record Decimal
      ((digits String)
       (exponent I64)))

    (define (positional (decimal Decimal)) (→ String)
      (let* ((digits (● decimal digits))
             (n (string-length digits))
             (k (● decimal exponent)))
        (cond ((<= k 0) (string-append "0." (make-string (negate k) #\0) digits))
              ((< k n) (string-append (substring digits 0 k) "." (substring digits k n)))
              (else (string-append digits (make-string (- k n) #\0) ".0")))))

    (define (scientific (decimal Decimal)) (→ String)
      (let* ((digits (● decimal digits))
             (n (string-length digits))
             (power (- (● decimal exponent) 1)))
        (string-append (substring digits 0 1)
                       (if (> n 1) (string-append "." (substring digits 1 n)) "")
                       (if (< power 0) "e-" "e+")
                       (i64->string (abs power)))))

    ;; ---- Printing reals: the shortest digits ----

    ;; The double is mant × 2^exp, and its rounding interval reaches minus
    ;; below and plus above in the same units: half the gaps to its
    ;; neighbours, the lower half as large for a power of two. The ends
    ;; round to the double itself when its mantissa is even.
    (record Decoded
      ((mant I64)
       (minus I64)
       (plus I64)
       (exp I64)
       (inclusive Bool)))

    (define (decode-real (value F64)) (→ Decoded)
      (let* ((bits (f64->bits value))
             (biased (i64-and (i64-shift-right bits 52) 2047))
             (fraction (i64-and bits 4503599627370495))
             (mant (if (= biased 0) (i64-shift-left fraction 1) (i64-or fraction 4503599627370496)))
             (even (= (i64-and mant 1) 0))
             (exp (- biased 1075)))
        (cond ((= biased 0) (new Decoded (mant mant) (minus 1) (plus 1) (exp exp) (inclusive even)))
              ((= fraction 0)
               (new Decoded
                 (mant (i64-shift-left mant 2))
                 (minus 1)
                 (plus 2)
                 (exp (- exp 2))
                 (inclusive even)))
              (else
               (new Decoded
                 (mant (i64-shift-left mant 1))
                 (minus 1)
                 (plus 1)
                 (exp (- exp 1))
                 (inclusive even))))))

    ;; Steele and White's free-format digits, as Dragon4 and Rust's flt2dec
    ;; produce them: with mant, minus and plus scaled so the first digit is
    ;; mant / scale, each step emits a digit and stops once the digits so
    ;; far, or one more than the last, fall inside the interval. Exact
    ;; arithmetic on big naturals keeps every step a decision, not a guess.
    (record Bounds
      ((mant (List I64))
       (minus (List I64))
       (plus (List I64))
       (scale (List I64))))

    (define (shortest-digits (value F64)) (→ Decimal)
      (let* ((decoded (decode-real value))
             (k (estimate-exponent (+ (● decoded mant) (● decoded plus)) (● decoded exp)))
             (rounding (if (● decoded inclusive) 1 0))
             (bounds (scaled-bounds decoded k)))
        (if (< (big-compare (● bounds scale) (big-add (● bounds mant) (● bounds plus) 0)) rounding)
            (next-digit bounds rounding (+ k 1) (Nil))
            (next-digit (bounds-times-ten bounds) rounding k (Nil)))))

    ;; About log10 of mant × 2^exp, rounded down, and at most one too small:
    ;; 1292913986 / 2^32 is just under log10 2.
    (define (estimate-exponent (mant I64) (exp I64)) (→ I64)
      (i64-shift-right (* (+ (bit-length (- mant 1)) exp) 1292913986) 32))

    (define (bit-length (n I64)) (→ I64)
      (if (= n 0) 0 (+ 1 (bit-length (i64-shift-right/logical n 1)))))

    ;; mant, minus and plus over scale, as naturals, divided by 10^k.
    (define (scaled-bounds (decoded Decoded) (k I64)) (→ Bounds)
      (let* ((exp (● decoded exp))
             (natural (lambda (n) (big-shift (big n) (max exp 0))))
             (bounds (new Bounds
                       (mant (natural (● decoded mant)))
                       (minus (natural (● decoded minus)))
                       (plus (natural (● decoded plus)))
                       (scale (big-shift (big 1) (max (negate exp) 0))))))
        (if (>= k 0)
            (Bounds-scale-set bounds (big-times-ten-to (● bounds scale) k))
            (new Bounds
              (mant (big-times-ten-to (● bounds mant) (negate k)))
              (minus (big-times-ten-to (● bounds minus) (negate k)))
              (plus (big-times-ten-to (● bounds plus) (negate k)))
              (scale (● bounds scale))))))

    (define (bounds-times-ten (bounds Bounds)) (→ Bounds)
      (new Bounds
        (mant (big-times-small (● bounds mant) 10 0))
        (minus (big-times-small (● bounds minus) 10 0))
        (plus (big-times-small (● bounds plus) 10 0))
        (scale (● bounds scale))))

    ;; `digits` so far, the last first. Rounding down leaves the digits
    ;; inside the interval when mant is below minus; rounding up does when
    ;; scale − mant is below plus. When both do, the nearer wins, a tie
    ;; rounding up.
    (define (next-digit (bounds Bounds) (rounding I64) (k I64) (digits (List I64))) (→ Decimal)
      (let* ((step (divide-digit (● bounds mant) (● bounds scale)))
             (mant (● step rest))
             (digits (Cons (● step digit) digits))
             (down (< (big-compare mant (● bounds minus)) rounding))
             (up (< (big-compare (● bounds scale) (big-add mant (● bounds plus) 0)) rounding)))
        (cond ((and up (or (not down) (>= (big-compare (big-shift mant 1) (● bounds scale)) 0)))
               (decimal-of (round-up-digits digits) k (+ (length digits) 1)))
              ((or down up) (decimal-of digits k (length digits)))
              (else
               (next-digit (bounds-times-ten (Bounds-mant-set bounds mant)) rounding k digits)))))

    ;; One more than the digits, the last first: a carry past the first
    ;; digit makes them 1 and zeros, one longer.
    (define (round-up-digits (digits (List I64))) (→ (List I64))
      (match digits
        ((Nil) (list 1))
        ((Cons digit rest)
         (if (= digit 9) (Cons 0 (round-up-digits rest)) (Cons (+ digit 1) rest)))))

    ;; Digits that grew past `count` carried into a new first digit.
    (define (decimal-of (digits (List I64)) (k I64) (count I64)) (→ Decimal)
      (new Decimal
        (digits (list->string (map (lambda (digit) (integer->char (+ digit 48))) (reverse digits))))
        (exponent (if (> (length digits) count) (+ k 1) k))))

    ;; The digit mant / scale, below 10, and the remainder, by subtracting
    ;; 8, 4, 2 and 1 times scale where they fit.
    (record Quotient
      ((digit I64)
       (rest (List I64))))

    (define (divide-digit (mant (List I64)) (scale (List I64))) (→ Quotient)
      (fold-left (lambda (division bit)
                   (let ((part (big-shift scale bit)))
                     (if (>= (big-compare (● division rest) part) 0)
                         (new Quotient
                           (digit (+ (● division digit) (i64-shift-left 1 bit)))
                           (rest (big-sub (● division rest) part 0)))
                         division)))
                 (new Quotient (digit 0) (rest mant))
                 (list 3 2 1 0)))

    ;; ---- Printing reals: big naturals ----

    ;; A natural as base-2^32 limbs, the least significant first, with no
    ;; zero limb on top: zero has none. Every limb is an I64 below 2^32, so
    ;; a limb times a factor below 2^31, plus a carry, fits in an I64.

    (define (big (n I64)) (→ (List I64))
      (if (= n 0) (Nil) (Cons (i64-and n 4294967295) (big (i64-shift-right/logical n 32)))))

    (define (big-add (a (List I64)) (b (List I64)) (carry I64)) (→ (List I64))
      (match a
        ((Nil) (if (= carry 0) b (big-add b (big carry) 0)))
        ((Cons x a-rest)
         (match b
           ((Nil) (big-add b a carry))
           ((Cons y b-rest)
            (let ((sum (+ (+ x y) carry)))
              (Cons (i64-and sum 4294967295) (big-add a-rest b-rest (i64-shift-right sum 32)))))))))

    ;; a − b, for a >= b.
    (define (big-sub (a (List I64)) (b (List I64)) (borrow I64)) (→ (List I64))
      (match a
        ((Nil) (Nil))
        ((Cons x a-rest)
         (let* ((y (match b ((Nil) 0) ((Cons y _) y)))
                (difference (- (- x y) borrow))
                (rest (big-sub a-rest
                               (match b ((Nil) (Nil)) ((Cons _ b-rest) b-rest))
                               (if (< difference 0) 1 0)))
                (limb (if (< difference 0) (+ difference 4294967296) difference)))
           (if (and (= limb 0) (null? rest)) (Nil) (Cons limb rest))))))

    (define (big-times-small (a (List I64)) (factor I64) (carry I64)) (→ (List I64))
      (match a
        ((Nil) (big carry))
        ((Cons x rest)
         (let ((product (+ (* x factor) carry)))
           (Cons (i64-and product 4294967295)
                 (big-times-small rest factor (i64-shift-right product 32)))))))

    (define (big-times-ten-to (a (List I64)) (k I64)) (→ (List I64))
      (if (>= k 9)
          (big-times-ten-to (big-times-small a 1000000000 0) (- k 9))
          (big-times-small a (fold-left (lambda (power _) (* power 10)) 1 (iota k)) 0)))

    ;; a × 2^bits: whole limbs of zeros below, then a shift within a limb.
    (define (big-shift (a (List I64)) (bits I64)) (→ (List I64))
      (if (null? a)
          a
          (append (map (lambda (_) 0) (iota (quotient bits 32)))
                  (big-times-small a (i64-shift-left 1 (modulo bits 32)) 0))))

    ;; -1, 0 or 1 as a is below, equal to or above b.
    (define (big-compare (a (List I64)) (b (List I64))) (→ I64)
      (let ((count-a (length a))
            (count-b (length b)))
        (cond ((< count-a count-b) -1)
              ((> count-a count-b) 1)
              (else (compare-limbs (reverse a) (reverse b))))))

    (define (compare-limbs (a (List I64)) (b (List I64))) (→ I64)
      (match a
        ((Nil) 0)
        ((Cons x a-rest)
         (match b
           ((Nil) 0)
           ((Cons y b-rest)
            (cond ((< x y) -1) ((> x y) 1) (else (compare-limbs a-rest b-rest))))))))

    ;; ---- Representing values ----

    ;; Representations are pure. Containers preserve their elements' notation,
    ;; including quotes and escapes; displaying a value still uses Show.
    (typeclass (Repr T)
      (declare (repr (value T)) (→ String)))

    ;; `(deriving Repr)` on a record or an enum is a use of one of these
    ;; macros, which the expander writes: the head with its parameters,
    ;; then each case as its name, the name as text and, for each field, a
    ;; fresh variable, the label and the label as text. A record is one
    ;; case, written as its construction; an enum's case as its call.

    (define-syntax derive-repr-record
      (syntax-rules ()
        ((_ (name param ...) (case text (field label label-text) ...))
         (instance (Repr (name param ...))
           (⊨ (Repr param) ...)
           (define repr
             (lambda (value)
               (match value
                 ((case field ...)
                  (string-concatenate
                   (list "(new "
                         text
                         (string-append " (" label-text " " (repr field) ")") ...
                         ")"))))))))))

    (define-syntax derive-repr-enum
      (syntax-rules ()
        ((_ (name param ...) (case text (field label label-text) ...) ...)
         (instance (Repr (name param ...))
           (⊨ (Repr param) ...)
           (define repr
             (lambda (value)
               (match value
                 ((case field ...)
                  (string-concatenate
                   (list "(" text (string-append " " (repr field)) ... ")"))) ...)))))))

    (instance (Repr I64)
      (define (repr (value I64)) (→ String)
        (i64->string value)))

    (instance (Repr I32)
      (define (repr (value I32)) (→ String)
        (i64->string (i32->i64 value))))

    (instance (Repr U8)
      (define (repr (value U8)) (→ String)
        (i64->string (i32->i64 (u8->i32 value)))))

    (instance (Repr F64)
      (define (repr (value F64)) (→ String)
        (f64->string value)))

    (instance (Repr F32)
      (define (repr (value F32)) (→ String)
        (f64->string (f32->f64 value))))

    (instance (Repr Bool)
      (define (repr (value Bool)) (→ String)
        (if value "#t" "#f")))

    (instance (Repr Unit)
      (define (repr (value Unit)) (→ String)
        "()"))

    (instance (Repr Char)
      (define (repr (char Char)) (→ String)

        (cond ((= char #\space) "#\\space")
              ((= char #\newline) "#\\newline")
              ((= char #\tab) "#\\tab")
              (else (string-append "#\\" (make-string 1 char))))))

    (instance (Repr String)
      (define (repr (text String)) (→ String)

        (string-append "\""
                       (string-concatenate (map repr-escape (string->list text)))
                       "\"")))

    (define (repr-escape (char Char)) (→ String)
      (cond ((= char #\") "\\\"")
            ((= char #\\) "\\\\")
            ((= char #\newline) "\\n")
            ((= char #\return) "\\r")
            ((= char #\tab) "\\t")
            (else (make-string 1 char))))

    (instance (Repr (List T))
      (⊨ (Repr T))
      (define (repr (items (List T))) (→ String)

        (string-append "(" (string-join (map repr items) " ") ")")))

    (instance (Repr (Array T))
      (⊨ (Repr T))
      (define (repr (items (Array T))) (→ String)

        (string-append "#(" (string-join (map repr (array->list items)) " ") ")")))

    (instance (Repr (Option T))
      (⊨ (Repr T))
      (define (repr (value (Option T))) (→ String)

        (match value
          ((Some item) (string-append "(Some " (repr item) ")"))
          ((None) "(None)"))))

    (instance (Repr (Result T E))
      (⊨ (Repr T) (Repr E))
      (define (repr (value (Result T E))) (→ String)

        (match value
          ((Ok item) (string-append "(Ok " (repr item) ")"))
          ((Err error) (string-append "(Err " (repr error) ")")))))

    (instance (Repr (Pair A B))
      (⊨ (Repr A) (Repr B))
      (define (repr (value (Pair A B))) (→ String)

        (match value
          ((Pair first second)
           (string-append "(new Pair (first " (repr first) ") (second " (repr second) "))")))))

    ))
