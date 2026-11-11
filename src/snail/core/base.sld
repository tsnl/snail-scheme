;; The standard prelude: core forms, derived syntax, numeric classes, text,
;; the immutable collections, and cells. Reading and writing arrays and
;; cells performs `mut`.
(define-library (snail core base)
  (export
   ●
   define lambda fn if begin let define-syntax syntax-rules quote : struct enum type
   typeclass
   instance
   define-instance-set
   with-instances
   match
   with-borrow borrow-copy
   ann
   type-convert
   try-convert
   type-test
   extern
   effect
   handle
   expose
   Any U8 I32 I64 F32 F64 Bool Char Unit String Array Vector Ref Bytes FnOnce FnMut Fn Borrow mut
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
   Option Some None Result Ok Err Pair Never absurd
   dyn-cast conversion-failed CastError
   CastReason TypeMismatch UnsupportedInstance ArgumentMismatch
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
   set! replace! Unboxed
   MutVector mut-vector mut-vector-length mut-vector-ref mut-vector-set! mut-vector-push!
   mut-vector-pop! mut-vector->vector
   Ref-contents
   Ref-contents-set!
   Ref-contents-replace!
   (rename Ref ref)
   (rename Ref-contents ref-get)
   (rename Ref-contents-set! ref-set!)
   (rename Ref-contents-replace! ref-replace!))
  (import
   (snail core forms)
   (except (snail core primitive)
           make-array
           array-length
           array-ref
           array-set!
           array->vector
           vector->array
           array-copy!
           vector-copy!)
   (rename (only (snail core primitive)
                 make-array
                 array-length
                 array-ref
                 array-set!
                 array->vector
                 vector->array
                 array-copy!
                 vector-copy!)
           (make-array primitive-make-array)
           (array-length primitive-array-length)
           (array-ref primitive-array-ref)
           (array-set! primitive-array-set!)
           (array->vector primitive-array->vector)
           (vector->array primitive-vector->array)
           (array-copy! primitive-array-copy!)
           (vector-copy! primitive-vector-copy!))
   (rename (only (snail core primitive) string-append) (string-append append-two-strings)))
  (begin

    ;; ---- Lexical borrowing ----

    (define-syntax with-borrow
      (syntax-rules ()
        ((_ (name owner) body ...)
         (let ((name (borrow owner))) body ...))))

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

    (typeclass (Num e T)
      (: + (dyn (Fn T T → T ! e)))
      (: - (dyn (Fn T T → T ! e)))
      (: * (dyn (Fn T T → T ! e)))
      (: negate (dyn (Fn T → T ! e))))

    (typeclass (Ord e T)
      (: = (dyn (Fn T T → Bool ! e)))
      (: < (dyn (Fn T T → Bool ! e)))
      (: <= (dyn (Fn T T → Bool ! e)))
      (: > (dyn (Fn T T → Bool ! e)))
      (: >= (dyn (Fn T T → Bool ! e))))

    (typeclass (Integral e T)
      (: quotient (dyn (Fn T T → T ! e)))
      (: remainder (dyn (Fn T T → T ! e)))
      (: modulo (impl (Fn T T → T ! e))))

    (typeclass (Fractional e T)
      (: / (dyn (Fn T T → T ! e)))
      (: sqrt (dyn (Fn T → T ! e)))
      (: floor (dyn (Fn T → T ! e)))
      (: ceiling (dyn (Fn T → T ! e)))
      (: round (dyn (Fn T → T ! e)))
      (: truncate (dyn (Fn T → T ! e))))

    (instance (Num (!) U8)
      (define + (lambda (a b) (i32->u8 (i32-add (u8->i32 a) (u8->i32 b)))))
      (define - (lambda (a b) (i32->u8 (i32-sub (u8->i32 a) (u8->i32 b)))))
      (define * (lambda (a b) (i32->u8 (i32-mul (u8->i32 a) (u8->i32 b)))))
      (define negate (lambda (a) (i32->u8 (i32-sub 0 (u8->i32 a))))))

    (instance (Ord (!) U8)
      (define = (lambda (a b) (i32-eq (u8->i32 a) (u8->i32 b))))
      (define < (lambda (a b) (i32-lt (u8->i32 a) (u8->i32 b))))
      (define <= (lambda (a b) (i32-le (u8->i32 a) (u8->i32 b))))
      (define > (lambda (a b) (i32-gt (u8->i32 a) (u8->i32 b))))
      (define >= (lambda (a b) (i32-ge (u8->i32 a) (u8->i32 b)))))

    (instance (Num (!) I32)
      (define + i32-add)
      (define - i32-sub)
      (define * i32-mul)
      (define negate (lambda (x) (i32-sub 0 x))))

    (instance (Num (!) I64)
      (define + i64-add)
      (define - i64-sub)
      (define * i64-mul)
      (define negate (lambda (x) (i64-sub 0 x))))

    (instance (Num (!) F32)
      (define + f32-add)
      (define - f32-sub)
      (define * f32-mul)
      (define negate f32-negate))

    (instance (Num (!) F64)
      (define + f64-add)
      (define - f64-sub)
      (define * f64-mul)
      (define negate f64-negate))

    (instance (Ord (!) I32)
      (define = i32-eq)
      (define < i32-lt)
      (define <= i32-le)
      (define > i32-gt)
      (define >= i32-ge))

    (instance (Ord (!) I64)
      (define = i64-eq)
      (define < i64-lt)
      (define <= i64-le)
      (define > i64-gt)
      (define >= i64-ge))

    (instance (Ord (!) F32)
      (define = f32-eq)
      (define < f32-lt)
      (define <= f32-le)
      (define > f32-gt)
      (define >= f32-ge))

    (instance (Ord (!) F64)
      (define = f64-eq)
      (define < f64-lt)
      (define <= f64-le)
      (define > f64-gt)
      (define >= f64-ge))

    (instance (Ord (!) Char)
      (define = (lambda (a b) (i32-eq (char->i32 a) (char->i32 b))))
      (define < (lambda (a b) (i32-lt (char->i32 a) (char->i32 b))))
      (define <= (lambda (a b) (i32-le (char->i32 a) (char->i32 b))))
      (define > (lambda (a b) (i32-gt (char->i32 a) (char->i32 b))))
      (define >= (lambda (a b) (i32-ge (char->i32 a) (char->i32 b)))))

    (instance (Ord (!) Bool)
      (define = (lambda (a b) (i32-eq (bool->i32 a) (bool->i32 b))))
      (define < (lambda (a b) (i32-lt (bool->i32 a) (bool->i32 b))))
      (define <= (lambda (a b) (i32-le (bool->i32 a) (bool->i32 b))))
      (define > (lambda (a b) (i32-gt (bool->i32 a) (bool->i32 b))))
      (define >= (lambda (a b) (i32-ge (bool->i32 a) (bool->i32 b)))))

    (instance (Ord (!) String)
      (define = string=?)
      (define < (lambda (a b) (i32-lt (string-compare a b) 0)))
      (define <= (lambda (a b) (i32-le (string-compare a b) 0)))
      (define > (lambda (a b) (i32-gt (string-compare a b) 0)))
      (define >= (lambda (a b) (i32-ge (string-compare a b) 0))))

    (instance (Integral (!) I32)
      (define quotient i32-quotient)
      (define remainder i32-remainder)
      (define modulo
        (lambda (a b) (let ((r (i32-remainder a b)))
                        (if (and (not (i32-eq r 0)) (not (= (i32-lt r 0) (i32-lt b 0))))
                            (i32-add r b)
                            r)))))

    (instance (Integral (!) I64)
      (define quotient i64-quotient)
      (define remainder i64-remainder)
      (define modulo
        (lambda (a b) (let ((r (i64-remainder a b)))
                        (if (and (not (i64-eq r 0)) (not (= (i64-lt r 0) (i64-lt b 0))))
                            (i64-add r b)
                            r)))))

    (instance (Fractional (!) F32)
      (define / f32-div)
      (define sqrt f32-sqrt)
      (define floor f32-floor)
      (define ceiling f32-ceiling)
      (define round f32-round)
      (define truncate f32-truncate))

    (instance (Fractional (!) F64)
      (define / f64-div)
      (define sqrt f64-sqrt)
      (define floor f64-floor)
      (define ceiling f64-ceiling)
      (define round f64-round)
      (define truncate f64-truncate))

    (define (abs (x T)) (→ T) (! e) (∀ T e) (⊨ (Num e T) (Ord e T) (Copy T))
      (if (< x (- x x)) (negate x) x))

    (define (min (a T) (b T)) (→ T) (! e) (∀ T e) (⊨ (Ord e T) (Copy T))
      (if (< b a) b a))

    (define (max (a T) (b T)) (→ T) (! e) (∀ T e) (⊨ (Ord e T) (Copy T))
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
    ;; object whose slots are the counter's, and `(set! (● r count) 1)`
    ;; writes one of them. The field's operations are exported
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

    (define (absurd (never Never)) (→ A) (∀ A)
      (match never))

    ;; ---- Dynamic conversions ----

    (enum CastReason
      (TypeMismatch)
      (UnsupportedInstance)
      (ArgumentMismatch))

    ;; Identities describe the mismatch without keeping its original value
    ;; alive. The expected names are known at the conversion boundary.
    (struct CastError
      ((reason CastReason)
       (expected (List String))
       (actual I64)
       (origin String)
       (method String)
       (argument I64)))

    (effect dyn-cast
      ((ctl conversion-failed (dyn (Fn CastError → Never)))))

    ;; ---- Callable contracts ----

    ;; The compiler establishes these contracts for concrete callables and
    ;; erased callable storage. Signature carries arguments, result and
    ;; effects together. Receiver access implies Fn -> FnMut -> FnOnce;
    ;; none of these classes implies Copy or a total effect row.
    (typeclass (Fn F Signature))
    (typeclass (FnMut F Signature))
    (typeclass (FnOnce F Signature))

    ;; ---- Releasing ----

    ;; `drop` releases a value without using it, and performs what
    ;; releasing it does, found from its type: nothing for an unrestricted
    ;; value, a FnOnce, or data with nothing linear in it; the method of the
    ;; type's instance, which names its row in its head; and otherwise a
    ;; drop of each linear field. A definition that drops a value of a type
    ;; variable A requires (Drop e A), with `e` in its row:
    ;;
    ;;     (instance (Drop (! log) Handle)
    ;;       (define drop (lambda (handle) ...)))
    (typeclass (Drop e T)
      (: drop (impl (Fn T → Unit ! e))))

    ;; ---- Cloning ----

    ;; `clone` duplicates a value, the one it is handed and a copy, and
    ;; performs what copying it does, found from its type as a drop's is:
    ;; nothing for an unrestricted value, which both halves share; the
    ;; method of the type's instance; and otherwise a clone of each linear
    ;; field. A FnOnce runs once, so it has none, and a type its library
    ;; made linear has one only by an instance. A definition that clones a
    ;; value of a type variable A requires (Clone e A).
    (typeclass (Clone e T)
      (: clone (impl (Fn T → (Pair T T) ! e))))

    ;; ---- Lists ----

    (enum (List T)
      (Nil)
      (Cons ((head T) (tail (List T)))))

    (define-syntax list
      (syntax-rules ()
        ((_) (Nil))
        ((_ item rest ...) (Cons item (list rest ...)))))

    (define (null? (items (List T))) (→ Bool) (∀ T) (⊨ (Copy T))
      (match items
        ((Nil) #t)
        ((Cons _ _) #f)))

    (define (length (items (List T))) (→ I64) (∀ T) (⊨ (Copy T))
      (fold-left (lambda (count item) (+ count 1)) 0 items))

    (define (reverse (items (List T))) (→ (List T)) (∀ T)
      (fold-left (lambda (reversed item) (Cons item reversed)) (Nil) items))

    (define (append (front (List T)) (back (List T))) (→ (List T)) (∀ T)
      (fold-right Cons back front))

    (define (concatenate (lists (List (List T)))) (→ (List T)) (∀ T)
      (fold-right append (Nil) lists))

    (define (map (f Callback) (items (List A)))
      (→ (List B))
      (! e)
      (∀ A B e Callback)
      (⊨ (Copy Callback) (Fn Callback A → B ! e))
      (reverse (fold-left (lambda (mapped item) (Cons (f item) mapped)) (Nil) items)))

    (define (map-indexed (f Callback) (items (List A)))
      (→ (List B))
      (! e)
      (∀ A B e Callback)
      (⊨ (Copy Callback) (Fn Callback I64 A → B ! e))
      (let loop ((items items) (index 0) (mapped (Nil)))
        (match items
          ((Nil) (reverse mapped))
          ((Cons item rest) (loop rest (+ index 1) (Cons (f index item) mapped))))))

    (define (for-each (f Callback) (items (List A)))
      (→ Unit)
      (! e)
      (∀ A e Callback)
      (⊨ (Copy Callback) (Fn Callback A → Unit ! e))
      (match items
        ((Nil) (unit))
        ((Cons item rest) (f item) (for-each f rest))))

    (define (filter (keep? Callback) (items (List A)))
      (→ (List A))
      (! e)
      (∀ A e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback A → Bool ! e))
      (reverse
       (fold-left (lambda (kept item) (if (keep? item) (Cons item kept) kept)) (Nil) items)))

    (define (fold-left (f Callback) (initial B) (items (List A)))
      (→ B)
      (! e)
      (∀ A B e Callback)
      (⊨ (Copy Callback) (Fn Callback B A → B ! e))
      (match items
        ((Nil) initial)
        ((Cons item rest) (fold-left f (f initial item) rest))))

    (define (fold-right (f Callback) (initial B) (items (List A)))
      (→ B)
      (! e)
      (∀ A B e Callback)
      (⊨ (Copy Callback) (Fn Callback A B → B ! e))
      (fold-left (lambda (result item) (f item result)) initial (reverse items)))

    (define (list-tail (items (List T)) (index I64)) (→ (List T)) (∀ T) (⊨ (Copy T))
      (if (= index 0)
          items
          (match items
            ((Cons _ rest) (list-tail rest (- index 1)))
            ((Nil) (panic "list-tail: index out of range")))))

    (define (list-ref (items (List T)) (index I64)) (→ T) (∀ T) (⊨ (Copy T))
      (match (list-tail items index)
        ((Cons item _) item)
        ((Nil) (panic "list-ref: index out of range"))))

    (define (any? (test Callback) (items (List A)))
      (→ Bool)
      (! e)
      (∀ A e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback A → Bool ! e))
      (match items
        ((Nil) #f)
        ((Cons item rest) (if (test item) #t (any? test rest)))))

    (define (every? (test Callback) (items (List A)))
      (→ Bool)
      (! e)
      (∀ A e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback A → Bool ! e))
      (match items
        ((Nil) #t)
        ((Cons item rest) (if (test item) (every? test rest) #f))))

    (define (find (test Callback) (items (List A)))
      (→ (Option A))
      (! e)
      (∀ A e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback A → Bool ! e))
      (match items
        ((Nil) (None))
        ((Cons item rest) (if (test item) (Some item) (find test rest)))))

    (define (member? (value A) (items (List A))) (→ Bool) (! e) (∀ A e) (⊨ (Ord e A) (Copy A))
      (any? (lambda (item) (= item value)) items))

    ;; Keeps the first of each group of equal items.

    (define (delete-duplicates (same? Callback) (items (List A)))
      (→ (List A))
      (! e)
      (∀ A e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback A A → Bool ! e))
      (reverse (fold-left (lambda (kept item)
                            (if (any? (lambda (other) (same? other item)) kept)
                                kept
                                (Cons item kept)))
                          (Nil) items)))

    (define (take (items (List T)) (count I64)) (→ (List T)) (∀ T) (⊨ (Copy T))
      (let loop ((items items) (count count) (taken (Nil)))
        (match items
          ((Cons item rest)
           (if (= count 0) (reverse taken) (loop rest (- count 1) (Cons item taken))))
          ((Nil) (reverse taken)))))

    (define (list-drop (items (List T)) (count I64)) (→ (List T)) (∀ T) (⊨ (Copy T))
      (if (= count 0)
          items
          (match items
            ((Cons _ rest) (list-drop rest (- count 1)))
            ((Nil) (Nil)))))

    ;; A stable merge sort: contiguous halves keep their order, and the
    ;; merge takes the left item first when neither precedes the other.
    ;; Comparing and splitting read the items, so their type must be Copy.

    (define (list-sort (before? Callback) (items (List T)))
      (→ (List T))
      (∀ T Callback)
      (⊨ (Copy T) (Copy Callback) (Fn Callback T T → Bool))
      (let ((half (quotient (length items) 2)))
        (if (= half 0)
            items
            (merge-sorted before?
                          (list-sort before? (take items half))
                          (list-sort before? (list-drop items half))))))

    (define (merge-sorted (before? Callback) (left (List T)) (right (List T)))
      (→ (List T))
      (∀ T Callback)
      (⊨ (Copy T) (Copy Callback) (Fn Callback T T → Bool))
      (match (Pair left right)
        ((Pair (Nil) _) right)
        ((Pair _ (Nil)) left)
        ((Pair (Cons a rest-a) (Cons b rest-b))
         (if (before? b a)
             (Cons b (merge-sorted before? left rest-b))
             (Cons a (merge-sorted before? rest-a right))))))

    (define (last (items (List T))) (→ (Option T)) (∀ T) (⊨ (Copy T))
      (match items
        ((Nil) (None))
        ((Cons item (Nil)) (Some item))
        ((Cons _ rest) (last rest))))

    (define (list-index (test Callback) (items (List A)))
      (→ (Option I64))
      (! e)
      (∀ A e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback A → Bool ! e))
      (let loop ((items items) (index 0))
        (match items
          ((Nil) (None))
          ((Cons item rest) (if (test item) (Some index) (loop rest (+ index 1)))))))

    ;; The value paired with the first occurrence of `key`.

    (define (assoc-ref (entries (List (Pair K V))) (key K))
      (→ (Option V))
      (! e)
      (∀ K V e)
      (⊨ (Ord e K) (Copy K) (Copy V))
      (match entries
        ((Nil) (None))
        ((Cons entry rest)
         (if (= (● entry first) key) (Some (● entry second)) (assoc-ref rest key)))))

    ;; Pairs the items of two lists, stopping at the end of the shorter.

    (define (zip (as (List A)) (bs (List B))) (→ (List (Pair A B))) (∀ A B) (⊨ (Copy A) (Copy B))
      (let loop ((as as) (bs bs) (pairs (Nil)))
        (match as
          ((Nil) (reverse pairs))
          ((Cons a more-as)
           (match bs
             ((Nil) (reverse pairs))
             ((Cons b more-bs) (loop more-as more-bs (Cons (Pair a b) pairs))))))))

    (define (iota (count I64)) (→ (List I64))
      (let loop ((index (- count 1)) (items (Nil)))
        (if (< index 0) items (loop (- index 1) (Cons index items)))))

    ;; ---- Unboxed elements ----

    ;; An array element is one Wasm slot, so the array operations require
    ;; `(Unboxed A)`: a scalar; a reference, such as a String, a Vector, a
    ;; cell, a closure, an enum or an Any; or a struct of one unboxed field.
    ;; A struct of several fields would be boxed in every element, so it is
    ;; refused: keep a struct of arrays instead, as typed arrays do. The
    ;; checker decides the class from a type's representation (check.sld,
    ;; "Solving"), and no instance can be declared. The operations are the
    ;; primitives under the requirement; mono replaces each with its target.
    (typeclass (Unboxed T))

    (define make-array
      (→ (dyn (Fn I64 A → (Array A) ! mut)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-make-array)

    (define array-length
      (→ (dyn (Fn (Array A) → I64)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-array-length)

    (define array-ref
      (→ (dyn (Fn (Array A) I64 → A ! mut)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-array-ref)

    (define array-set!
      (→ (dyn (Fn (Array A) I64 A → Unit ! mut)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-array-set!)

    (define array->vector
      (→ (dyn (Fn (Array A) → (Vector A) ! mut)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-array->vector)

    (define vector->array
      (→ (dyn (Fn (Vector A) → (Array A) ! mut)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-vector->array)

    (define array-copy!
      (→ (dyn (Fn (Array A) I64 (Array A) I64 I64 → Unit ! mut)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-array-copy!)

    (define vector-copy!
      (→ (dyn (Fn (Array A) I64 (Vector A) I64 I64 → Unit ! mut)))
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      primitive-vector-copy!)

    ;; ---- Vectors and arrays ----

    (define (vector-map (f Callback) (items (Vector A)))
      (→ (Vector B))
      (! e)
      (∀ A B e Callback)
      (⊨ (Copy A) (Copy B) (Copy Callback) (Fn Callback A → B ! e))
      (vector-generate (vector-length items) (lambda (index) (f (vector-ref items index)))))

    (define (vector-for-each (f Callback) (items (Vector A)))
      (→ Unit)
      (! e)
      (∀ A e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback A → Unit ! e))
      (let loop ((index 0))
        (when (< index (vector-length items))
          (f (vector-ref items index))
          (loop (+ index 1)))))

    (define (vector-fold (f Callback) (initial B) (items (Vector A)))
      (→ B)
      (! e)
      (∀ A B e Callback)
      (⊨ (Copy A) (Copy Callback) (Fn Callback B A → B ! e))
      (let loop ((index 0) (result initial))
        (if (< index (vector-length items))
            (loop (+ index 1) (f result (vector-ref items index)))
            result)))

    (define (vector->list (items (Vector T))) (→ (List T)) (∀ T) (⊨ (Copy T))
      (let loop ((index (- (vector-length items) 1)) (result (Nil)))
        (if (< index 0) result (loop (- index 1) (Cons (vector-ref items index) result)))))

    ;; The elements are taken in order from a cursor local to this call, so
    ;; the conversion is total and needs no array, whose elements would have
    ;; to be unboxed.

    (define (list->vector (items (List T))) (→ (Vector T)) (∀ T) (⊨ (Copy T))
      (let ((rest (Ref items)))
        (vector-generate (length items)
                         (lambda (index)
                           (match (Ref-contents rest)
                             ((Cons first remaining)
                              (Ref-contents-set! rest remaining)
                              first)
                             ((Nil) (panic "list->vector: too few items")))))))

    ;; One vector of the total length, filled from a cursor over the vectors
    ;; that skips the empty ones; the cursor is local to this call.

    (define (vector-concatenate (vectors (List (Vector T)))) (→ (Vector T)) (∀ T) (⊨ (Copy T))
      (let ((cursor (Ref (Pair vectors 0))))
        (vector-generate
         (fold-left (lambda (total items) (+ total (vector-length items))) 0 vectors)
         (lambda (index)
           (let next ()
             (match (Ref-contents cursor)
               ((Pair (Cons items rest) offset)
                (if (< offset (vector-length items))
                    (begin
                      (Ref-contents-set! cursor (Pair (Cons items rest) (+ offset 1)))
                      (vector-ref items offset))
                    (begin
                      (Ref-contents-set! cursor (Pair rest 0))
                      (next))))
               ((Pair (Nil) _) (panic "vector-concatenate: too few elements"))))))))

    ;; ---- Growable vectors ----

    ;; A MutVector grows at its end, as Rust's Vec does, over an array it
    ;; replaces with one twice as long when full. The handle is a value
    ;; holding one cell, so two names for a vector see the same writes, and
    ;; its elements are unboxed, as every array's are.
    (struct (MutVector A)
      ((state (Ref (Grown A)))))

    ;; The elements in use and the array holding them, None before the first
    ;; push, since an array needs an element to start from.
    (struct (Grown A)
      ((length I64)
       (items (Option (Array A)))))

    (define (mut-vector) (→ (MutVector A)) (∀ A) (⊨ (Copy A) (Unboxed A))
      (MutVector (Ref (Grown 0 (None)))))

    (define (mut-vector-length (vector (MutVector A)))
      (→ I64)
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (● (Ref-contents (● vector state)) length))

    (define (mut-vector-ref (vector (MutVector A)) (index I64))
      (→ A)
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (array-ref (mut-vector-items vector index) index))

    (define (mut-vector-set! (vector (MutVector A)) (index I64) (item A))
      (→ Unit)
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (array-set! (mut-vector-items vector index) index item))

    ;; The array, once `index` is in use.

    (define (mut-vector-items (vector (MutVector A)) (index I64))
      (→ (Array A))
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (match (Ref-contents (● vector state))
        ((Grown length (Some items))
         (if (and (<= 0 index) (< index length))
             items
             (panic "mut-vector: index out of range")))
        ((Grown _ (None)) (panic "mut-vector: index out of range"))))

    (define (mut-vector-push! (vector (MutVector A)) (item A))
      (→ Unit)
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (let ((cell (● vector state)))
        (match (Ref-contents cell)
          ((Grown length held)
           (let ((items (room-for length held item)))
             (array-set! items length item)
             (Ref-contents-set! cell (Grown (+ length 1) (Some items))))))))

    ;; An array with room at `length`: the one held, a longer copy of it, or
    ;; the first array, started from the element being pushed.

    (define (room-for (length I64) (held (Option (Array A))) (item A))
      (→ (Array A))
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (match held
        ((None) (make-array 4 item))
        ((Some items)
         (if (< length (array-length items))
             items
             (let ((longer (make-array (* 2 (array-length items)) item)))
               (array-copy! longer 0 items 0 length)
               longer)))))

    (define (mut-vector-pop! (vector (MutVector A)))
      (→ (Option A))
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (let ((cell (● vector state)))
        (match (Ref-contents cell)
          ((Grown length (Some items))
           (if (> length 0)
               (begin
                 (Ref-contents-set! cell (Grown (- length 1) (Some items)))
                 (Some (array-ref items (- length 1))))
               (None)))
          ((Grown _ (None)) (None)))))

    (define (mut-vector->vector (vector (MutVector A)))
      (→ (Vector A))
      (! mut)
      (∀ A)
      (⊨ (Copy A) (Unboxed A))
      (match (Ref-contents (● vector state))
        ((Grown length (Some items))
         (vector-generate length (lambda (index) (array-ref items index))))
        ((Grown _ (None))
         (vector-generate 0 (lambda (index) (panic "mut-vector->vector: empty"))))))

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
      (vector->string (list->vector chars)))

    ;; Copies each string once into one array of the total length. The array
    ;; is local to this call.

    (define (string-concatenate (texts (List String))) (→ String)
      (let ((chars
             (make-array (fold-left (lambda (total text) (+ total (string-length text))) 0 texts)
                         #\space)))
        (fold-left (lambda (offset text)
                     (vector-copy! chars offset (string->vector text) 0 (string-length text))
                     (+ offset (string-length text)))
                   0 texts)
        (vector->string (array->vector chars))))

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

    (typeclass (Show e T)
      (: show (dyn (Fn T → String ! e))))

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

    (instance (Show (!) I64)
      (define show i64->string))

    (instance (Show (!) U8)
      (define show (lambda (n) (i64->string (i32->i64 (u8->i32 n))))))

    (instance (Show (!) I32)
      (define show (lambda (n) (i64->string (i32->i64 n)))))

    (instance (Show (!) Bool)
      (define show (lambda (value) (if value "#t" "#f"))))

    (instance (Show (!) Char)
      (define show (lambda (char) (make-string 1 char))))

    (instance (Show (!) String)
      (define show (lambda (text) text)))

    (instance (Show (!) Unit)
      (define show (lambda (value) "()")))

    (instance (Show (! e) (List T))
      (⊨ (Show e T))
      (define show
        (lambda (items)
          (string-append "(" (string-append (string-join (map show items) " ") ")")))))

    (instance (Show (! e) (Option T))
      (⊨ (Show e T))
      (define show
        (lambda (value) (match value
                          ((Some x) (string-append "(Some " (string-append (show x) ")")))
                          ((None) "(None)")))))

    (instance (Show (!) F64)
      (define show f64->string))

    (instance (Show (!) F32)
      (define show (lambda (value) (f64->string (f32->f64 value)))))

    ;; Copy the runtime's scratch text before returning. string-generate calls
    ;; only this private reader, so no user conversion can overwrite it.
    (extern real-text "snail.core.support" "snail:datum/real-text" (impl (Fn F64 → I32)))
    (extern text-character
            "snail.core.support"
            "snail:datum/text-character"
            (impl (Fn I32 → Char)))

    (define (f64->string (value F64)) (→ String)
      (string-generate (i32->i64 (real-text value))
                       (lambda (index) (text-character (i64->i32 index)))))

    ))
