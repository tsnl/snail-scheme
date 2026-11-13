;; The standard prelude: core forms, derived syntax, numeric classes, text,
;; collections and mutable heap objects. Writes perform `mut`; reads are pure.
(define-library (snail core base)
  (export
   ●
   define lambda if begin let define-syntax syntax-rules quote : struct enum type
   typeclass
   instance
   match
   ann
   downcast
   extern
   effect
   handle
   expose
   Any U8 I32 I64 F32 F64 Bool Char Unit String Vector Bytes FnOnce Fn Rc WeakRc mut
   rc rc-get rc-downgrade weak-rc-upgrade
   u8->i32 i32->u8
   let* letrec cond case when unless and or do
   not unit panic unsafe-total once call-once Drop drop
   Num + - * negate abs
   Ord = < <= > >= min max
   Integral quotient remainder modulo
   Fractional / sqrt floor ceiling round truncate
   i32->i64 i64->i32 i64->f64 f64->i64 i32->f64 f64->i32 f32->f64 f64->f32 i64->f32 f32->i64
   i32->f32 f32->i32
   f32->bits bits->f32 f64->bits bits->f64
   Show show i64->string string->i64 f64->string
   Repr repr
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
   set! replace!)
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

    (typeclass (Num e T)
      (: + (Fn T T → T ! e))
      (: - (Fn T T → T ! e))
      (: * (Fn T T → T ! e))
      (: negate (Fn T → T ! e)))

    (typeclass (Ord e T)
      (: = (Fn T T → Bool ! e))
      (: < (Fn T T → Bool ! e))
      (: <= (Fn T T → Bool ! e))
      (: > (Fn T T → Bool ! e))
      (: >= (Fn T T → Bool ! e)))

    (typeclass (Integral e T)
      (: quotient (Fn T T → T ! e))
      (: remainder (Fn T T → T ! e))
      (: modulo (Fn T T → T ! e)))

    (typeclass (Fractional e T)
      (: / (Fn T T → T ! e))
      (: sqrt (Fn T → T ! e))
      (: floor (Fn T → T ! e))
      (: ceiling (Fn T → T ! e))
      (: round (Fn T → T ! e))
      (: truncate (Fn T → T ! e)))

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

    (define (abs (x T))
      (→ T)
      (! e)
      (∀ (T e))
      (⊨ (Num e T) (Ord e T) (Copy T) (Drop e T))
      (if (< x (- x x)) (negate x) x))

    (define (min (a T) (b T))
      (→ T)
      (! e)
      (∀ (T e))
      (⊨ (Ord e T) (Copy T) (Drop e T))
      (if (< b a) b a))

    (define (max (a T) (b T))
      (→ T)
      (! e)
      (∀ (T e))
      (⊨ (Ord e T) (Copy T) (Drop e T))
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

    ;; The type with no values. An operation that answers Never never
    ;; returns to its performer, so its handler is handed no `resume`, and
    ;; `absurd` lets the code after such a call have any type: a match on a
    ;; value of a type with no cases needs no clauses.
    (enum Never)

    (define (absurd (never Never)) (→ A) (∀ (A))
      (match never))

    ;; ---- Releasing ----

    ;; `drop` consumes a linear value or releases one shared owner. The
    ;; final shared owner releases its fields; Rc runs its payload finalizer.
    ;; A FnOnce drops its uncalled captures. Uncounted values need no cleanup.
    ;; The Drop constraint records the effects this cleanup may perform.
    (typeclass (Drop e T)
      (: drop (Fn T → Unit ! e)))

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
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (match items
        ((Nil) #t)
        ((Cons _ _) #f)))

    (define (length (items (List T)))
      (→ I64)
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
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
      (⊨ (Copy A) (Drop e A))
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
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (if (= index 0)
          items
          (match items
            ((Cons _ rest) (list-tail rest (- index 1)))
            ((Nil) (panic "list-tail: index out of range")))))

    (define (list-ref (items (List T)) (index I64))
      (→ T)
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (match (list-tail items index)
        ((Cons item _) item)
        ((Nil) (panic "list-ref: index out of range"))))

    (define (any? (test (Fn A → Bool ! e)) (items (List A)))
      (→ Bool)
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (match items
        ((Nil) #f)
        ((Cons item rest) (if (test item) #t (any? test rest)))))

    (define (every? (test (Fn A → Bool ! e)) (items (List A)))
      (→ Bool)
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (match items
        ((Nil) #t)
        ((Cons item rest) (if (test item) (every? test rest) #f))))

    (define (find (test (Fn A → Bool ! e)) (items (List A)))
      (→ (Option A))
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (match items
        ((Nil) (None))
        ((Cons item rest) (if (test item) (Some item) (find test rest)))))

    (define (member? (value A) (items (List A)))
      (→ Bool)
      (! e)
      (∀ (A e))
      (⊨ (Ord e A) (Copy A) (Drop e A))
      (any? (lambda (item) (= item value)) items))

    ;; Keeps the first of each group of equal items.

    (define (delete-duplicates (same? (Fn A A → Bool ! e)) (items (List A)))
      (→ (List A))
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (reverse (fold-left (lambda (kept item)
                            (if (any? (lambda (other) (same? other item)) kept)
                                kept
                                (Cons item kept)))
                          (Nil) items)))

    (define (take (items (List T)) (count I64))
      (→ (List T))
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (let loop ((items items) (count count) (taken (Nil)))
        (match items
          ((Cons item rest)
           (if (= count 0) (reverse taken) (loop rest (- count 1) (Cons item taken))))
          ((Nil) (reverse taken)))))

    (define (list-drop (items (List T)) (count I64))
      (→ (List T))
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (if (= count 0)
          items
          (match items
            ((Cons _ rest) (list-drop rest (- count 1)))
            ((Nil) (Nil)))))

    ;; A stable merge sort: contiguous halves keep their order, and the
    ;; merge takes the left item first when neither precedes the other.
    ;; Comparing and splitting read the items, so their type must be Copy.

    (define (list-sort (before? (Fn T T → Bool ! e)) (items (List T)))
      (→ (List T))
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (let ((half (quotient (length items) 2)))
        (if (= half 0)
            items
            (merge-sorted before?
                          (list-sort before? (take items half))
                          (list-sort before? (list-drop items half))))))

    (define (merge-sorted (before? (Fn T T → Bool ! e)) (left (List T)) (right (List T)))
      (→ (List T)) (! e) (∀ (T e)) (⊨ (Copy T) (Drop e T))
      ;; The merge is linear in the list length, but uses constant stack.
      ;; Equal elements come from the left run first, preserving stability.
      (let loop ((left left) (right right) (reversed (Nil)))
        (match (Pair left right)
          ((Pair (Nil) _) (fold-left (lambda (rest item) (Cons item rest)) right reversed))
          ((Pair _ (Nil)) (fold-left (lambda (rest item) (Cons item rest)) left reversed))
          ((Pair (Cons a rest-a) (Cons b rest-b))
           (if (before? b a) (loop left rest-b (Cons b reversed))
               (loop rest-a right (Cons a reversed)))))))

    (define (last (items (List T)))
      (→ (Option T))
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (match items
        ((Nil) (None))
        ((Cons item (Nil)) (Some item))
        ((Cons _ rest) (last rest))))

    (define (list-index (test (Fn A → Bool ! e)) (items (List A)))
      (→ (Option I64))
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (let loop ((items items) (index 0))
        (match items
          ((Nil) (None))
          ((Cons item rest) (if (test item) (Some index) (loop rest (+ index 1)))))))

    ;; The value paired with the first occurrence of `key`.

    (define (assoc-ref (entries (List (Pair K V))) (key K))
      (→ (Option V))
      (! e)
      (∀ (K V e))
      (⊨ (Ord e K) (Copy K) (Copy V) (Drop e K) (Drop e V))
      (match entries
        ((Nil) (None))
        ((Cons entry rest)
         (if (= (● entry first) key) (Some (● entry second)) (assoc-ref rest key)))))

    ;; Pairs the items of two lists, stopping at the end of the shorter.

    (define (zip (as (List A)) (bs (List B)))
      (→ (List (Pair A B)))
      (! e)
      (∀ (A B e))
      (⊨ (Copy A) (Copy B) (Drop e A) (Drop e B))
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

    ;; ---- Vectors ----

    (define (vector-map (f (Fn A → B ! e)) (items (Vector A)))
      (→ (Vector B))
      (! e)
      (∀ (A B e))
      (⊨ (Copy A) (Copy B) (Drop e A))
      (vector-generate (vector-length items) (lambda (index) (f (vector-ref items index)))))

    (define (vector-for-each (f (Fn A → Unit ! e)) (items (Vector A)))
      (→ Unit)
      (! e)
      (∀ (A e))
      (⊨ (Copy A) (Drop e A))
      (let loop ((index 0))
        (when (< index (vector-length items))
          (f (vector-ref items index))
          (loop (+ index 1)))))

    (define (vector-fold (f (Fn B A → B ! e)) (initial B) (items (Vector A)))
      (→ B)
      (! e)
      (∀ (A B e))
      (⊨ (Copy A) (Drop e A))
      (let loop ((index 0) (result initial))
        (if (< index (vector-length items))
            (loop (+ index 1) (f result (vector-ref items index)))
            result)))

    (define (vector->list (items (Vector T)))
      (→ (List T))
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (let loop ((index (- (vector-length items) 1)) (result (Nil)))
        (if (< index 0) result (loop (- index 1) (Cons (vector-ref items index) result)))))

    ;; Local cursors give generation a sequential input without exposing
    ;; mutable storage outside these total conversions.
    (struct (ListCursor A)
      ((remaining (List A))))

    (define (list->vector (items (List T)))
      (→ (Vector T))
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (unsafe-total (ann (lambda () (let ((cursor (ListCursor items)))
                                      (vector-generate (length items)
                                                       (lambda (index)
                                                         (match (● cursor remaining)
                                                           ((Cons first rest)
                                                            (set! (● cursor remaining) rest)
                                                            first)
                                                           ((Nil)
                                                            (panic
                                                             "list->vector: too few items")))))))
                         (Fn → (Vector T) ! mut e))))

    (struct (VectorCursor A)
      ((vectors (List (Vector A)))
       (offset I64)))

    (define (vector-concatenate (vectors (List (Vector T))))
      (→ (Vector T))
      (! e)
      (∀ (T e))
      (⊨ (Copy T) (Drop e T))
      (unsafe-total (ann (lambda () (let ((cursor (VectorCursor vectors 0)))
                                      (vector-generate
                                       (fold-left
                                        (lambda (total items) (+ total (vector-length items)))
                                        0
                                        vectors)
                                       (lambda (index)
                                         (let next ()
                                           (match (● cursor vectors)
                                             ((Cons items rest)
                                              (let ((offset (● cursor offset)))
                                                (if (< offset (vector-length items))
                                                    (begin
                                                      (set! (● cursor offset) (+ offset 1))
                                                      (vector-ref items offset))
                                                    (begin
                                                      (set! (● cursor vectors) rest)
                                                      (set! (● cursor offset) 0)
                                                      (next)))))
                                             ((Nil)
                                              (panic "vector-concatenate: too few elements"))))))))
                         (Fn → (Vector T) ! mut e))))

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
      (unsafe-total (lambda () (let ((chars
                                      (make-vector (fold-left (lambda (total text)
                                                                (+ total (string-length text)))
                                                              0
                                                              texts)
                                                   #\space)))
                                 (fold-left (lambda (offset text)
                                              (vector-copy! chars
                                                            offset
                                                            (string->vector text)
                                                            0
                                                            (string-length text))
                                              (+ offset (string-length text)))
                                            0 texts)
                                 (vector->string chars)))))

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
      (: show (Fn T → String ! e)))

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

    (instance (Show (!) F64)
      (define show f64->string))

    (instance (Show (!) F32)
      (define show (lambda (value) (f64->string (f32->f64 value)))))

    ;; Copy the runtime's scratch text before returning. string-generate calls
    ;; only this private reader, so no user conversion can overwrite it.
    (extern real-text "snail.core.support" "snail:datum/real-text" (Fn F64 → I32))
    (extern text-character
            "snail.core.support"
            "snail:datum/text-character"
            (Fn I32 → Char))

    (define (f64->string (value F64)) (→ String)
      (string-generate (i32->i64 (real-text value))
                       (lambda (index) (text-character (i64->i32 index)))))

    ;; ---- Representing values ----

    ;; Representations are pure. Containers preserve their elements' notation,
    ;; including quotes and escapes; displaying a value still uses Show.
    (typeclass (Repr T)
      (: repr (Fn T → String)))

    (instance (Repr I64)
      (define repr i64->string))

    (instance (Repr I32)
      (define repr (lambda (value) (i64->string (i32->i64 value)))))

    (instance (Repr U8)
      (define repr (lambda (value) (i64->string (i32->i64 (u8->i32 value))))))

    (instance (Repr F64)
      (define repr f64->string))

    (instance (Repr F32)
      (define repr (lambda (value) (f64->string (f32->f64 value)))))

    (instance (Repr Bool)
      (define repr (lambda (value) (if value "#t" "#f"))))

    (instance (Repr Unit)
      (define repr (lambda (value) "()")))

    (instance (Repr Char)
      (define repr (lambda (char)
                     (cond ((= char #\space) "#\\space")
                           ((= char #\newline) "#\\newline")
                           ((= char #\tab) "#\\tab")
                           (else (string-append "#\\" (make-string 1 char)))))))

    (instance (Repr String)
      (define repr (lambda (text)
                     (string-append "\""
                                    (string-concatenate (map repr-escape (string->list text)))
                                    "\""))))

    (define (repr-escape (char Char)) (→ String)
      (cond ((= char #\") "\\\"")
            ((= char #\\) "\\\\")
            ((= char #\newline) "\\n")
            ((= char #\return) "\\r")
            ((= char #\tab) "\\t")
            (else (make-string 1 char))))

    (instance (Repr (List T))
      (⊨ (Repr T))
      (define repr (lambda (items)
                     (string-append "(" (string-join (map repr items) " ") ")"))))

    (instance (Repr (Vector T))
      (⊨ (Repr T) (Copy T) (Drop (!) T))
      (define repr (lambda (items)
                     (string-append "#(" (string-join (map repr (vector->list items)) " ") ")"))))

    (instance (Repr (Option T))
      (⊨ (Repr T))
      (define repr (lambda (value)
                     (match value
                       ((Some item) (string-append "(Some " (repr item) ")"))
                       ((None) "(None)")))))

    (instance (Repr (Result T E))
      (⊨ (Repr T) (Repr E))
      (define repr (lambda (value)
                     (match value
                       ((Ok item) (string-append "(Ok " (repr item) ")"))
                       ((Err error) (string-append "(Err " (repr error) ")"))))))

    (instance (Repr (Pair A B))
      (⊨ (Repr A) (Repr B))
      (define repr (lambda (value)
                     (match value
                       ((Pair first second)
                        (string-append "(Pair " (repr first) " " (repr second) ")"))))))

    ))
