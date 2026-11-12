;; Query: when one instance overlaps another on their selecting types, as
;; the old compiler's `head-overlaps?` (src/snail/shell/compiler/core.sld)
;; decides it, and whether two of the instances active under some sets
;; overlap, as its `check-active-instances` asks it. `cohere` asks the
;; first of each instance a library declares and the second of each
;; instance scope; the checks of a `with-instances` expression and of a
;; definition under scopes, which the old checker makes, will ask the
;; second too. Both are refused with the one message `overlap-problem`.
;;
;; The relation is asymmetric: it asks whether an instance `a` overlaps an
;; instance `b`. They overlap when they are of one class and their
;; selecting types, which (snail compiler dispatch listing) says, are as
;; many, each of `a`'s overlapping `b`'s at its position. A type of `a`
;; overlaps a type of `b`:
;;
;; - a data type or a builtin, the same one whose arguments it overlaps in
;;   turn, as many, or a variable; nothing else;
;; - a callable other than a bare function, a callable of the same former
;;   and contract whatever its arrow, or a variable; code, code whatever
;;   its arrow, or a variable; nothing else;
;; - a bare function, `dyn (Fn ...)`, a variable or a row: anything.
;;
;; The old compiler writes `dyn (Fn ...)` as a function type, which its
;; rule lets overlap anything, and every other callable and code as a type
;; constructor applied to the arrow, which a function type is. So
;; `(Probe (dyn (Fn I64 -> I64)))` overlaps `(Probe I64)`, but `(Probe I64)`
;; does not overlap it (tests/programs/error-asymmetric-overlap.sld and
;; asymmetric-overlap.sld). A repeated variable is not unified: `(Pair a a)`
;; overlaps `(Pair I64 F64)`. The rule is sound for one-way matching
;; (snail compiler dispatch matching), by which an instance is chosen: when
;; some types match both heads, each head overlaps the other, so an
;; instance that overlaps none before it is never chosen beside one.
(define-library (snail compiler dispatch overlap)
  (export
   overlaps?
   active-overlap?
   overlap-problem)
  (import
   (snail core base)
   (only (snail compiler expand language) Global ClassRef Dyn FnContract)
   (only (snail compiler declare language) Type Con Callable Code Row Var)
   (only (snail compiler declare equality) same-global? same-former? same-contract?)
   (snail compiler dispatch listing))
  (begin

    ;; ---- Overlap ----

    ;; Whether `listed` overlaps `other`, the one asked about first.
    (: overlaps? (impl (Fn Listed Listed -> Bool)))
    (define (overlaps? listed other)
      (and (same-class? (listed-class listed) (listed-class other))
           (types-overlap? (selecting-types listed) (selecting-types other))))

    (: types-overlap? (impl (Fn (List Type) (List Type) -> Bool)))
    (define (types-overlap? types others)
      (and (= (length types) (length others))
           (every? (lambda (pair) (type-overlaps? (::first pair) (::second pair)))
                   (zip types others))))

    ;; Whether `type`, of the instance asked about, overlaps `other`, at
    ;; the same place in the other's head.
    (: type-overlaps? (impl (Fn Type Type -> Bool)))
    (define (type-overlaps? type other)
      (match type
        ((Con global arguments)
         (match other
           ((Con other-global others)
            (and (same-global? global other-global) (types-overlap? arguments others)))
           ((Var _) #t)
           (_ #f)))
        ;; The old compiler's function type, `dyn (Fn ...)`.
        ((Callable (Dyn) (FnContract) _) #t)
        ((Callable former contract _)
         (match other
           ((Callable other-former other-contract _)
            (and (same-former? former other-former) (same-contract? contract other-contract)))
           ((Var _) #t)
           (_ #f)))
        ((Code _)
         (match other
           ((Code _) #t)
           ((Var _) #t)
           (_ #f)))
        ((Row _) #t)
        ((Var _) #t)))

    ;; ---- Active instances ----

    ;; Whether two of `instances` that are active under `sets` overlap:
    ;; whether one overlaps another of its class, whichever is written
    ;; first. Every ordered pair of instances at two places is asked, so an
    ;; instance is never compared with itself, and two overlap here when
    ;; either overlaps the other.
    (: active-overlap? (impl (Fn (List Global) (List Listed) -> Bool)))
    (define (active-overlap? sets instances)
      (any? (lambda (class) (overlap-among? (::second class)))
            (by-class (filter (lambda (listed) (active? sets listed)) instances))))

    ;; Whether one of `instances`, all of one class, overlaps another: each
    ;; asked about every other, those before it and those after it.
    (: overlap-among? (impl (Fn (List Listed) -> Bool)))
    (define (overlap-among? instances)
      (let loop ((before (Nil))
                 (rest instances))
        (match rest
          ((Nil) #f)
          ((Cons listed after)
           (or (any? (lambda (other) (overlaps? listed other)) before)
               (any? (lambda (other) (overlaps? listed other)) after)
               (loop (Cons listed before) after))))))

    ;; Each class of `instances` with its instances, so that only instances
    ;; of one class are paired, as the old compiler pairs them class by
    ;; class. Whether two overlap depends on no order, so neither the
    ;; classes nor the instances of one are kept in order.
    (: by-class (impl (Fn (List Listed) -> (List (Pair ClassRef (List Listed))))))
    (define (by-class instances)
      (fold-left (lambda (classes listed) (with-classed listed classes)) (Nil) instances))

    (: with-classed
       (impl
        (Fn Listed (List (Pair ClassRef (List Listed))) -> (List (Pair ClassRef (List Listed))))))
    (define (with-classed listed classes)
      (match classes
        ((Nil) (list (Pair (listed-class listed) (list listed))))
        ((Cons class rest)
         (if (same-class? (listed-class listed) (::first class))
             (Cons (Pair (::first class) (Cons listed (::second class))) rest)
             (Cons class (with-classed listed rest))))))

    ;; ---- Messages ----

    ;; The old compiler's refusal, at the instance or at the scope.
    (: overlap-problem String)
    (define overlap-problem
      "this instance overlaps another instance of the class on its input types")

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-overlap)
    (import
     (snail compiler source)
     (only (snail compiler expand language)
           ClassGlobal
           FieldClass
           Impl
           FnMutContract
           FnOnceContract)
     (only (snail compiler declare language)
           Data
           DataCase
           DataField
           StructData
           Arrow
           Effects
           Written)
     (only (snail compiler declare forms) forms-library)
     (snail compiler dispatch language)
     (snail stage0 testing))
    (begin
      (define (test-overlap)
        (test-data-types)
        (test-callables)
        (test-variables)
        (test-instances)
        (test-active))

      (define main (list "main"))

      (define (at line)
        (Loc "t.sld" line 1))

      (define (builtin name)
        (Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define any-type (builtin "Any"))

      (define (list-of type)
        (Con (Global (list "snail" "core" "base") "List" 0) (list type)))

      (define a (Var (Written "a")))
      (define b (Var (Written "b")))

      (define (callable former contract parameter result)
        (Callable former contract (Arrow (list parameter) result (Effects (list) (None)))))

      (define (code parameter result)
        (Code (Arrow (list parameter) result (Effects (list) (None)))))

      (define bare (callable (Dyn) (FnContract) i64 i64))

      ;; An instance of `class` at `types`, written at `line`, in `set`.
      (define (instance-of class types line set)
        (ListedInstance (Instance (Global main (::name class) line)
                                  (ClassGlobal class)
                                  (list)
                                  types
                                  (list)
                                  (list)
                                  (list)
                                  (list)
                                  (at line))
                        set))

      (define probe-class (Global main "Probe" 0))

      (define (probe types line)
        (instance-of probe-class types line (None)))

      ;; Whether `(Probe type)` overlaps `(Probe other)`.
      (define (type-overlap? type other)
        (overlaps? (probe (list type) 1) (probe (list other) 2)))

      ;; A data type overlaps the same type whose arguments it overlaps, and
      ;; a variable: Any is a type like any other.
      (define (test-data-types)
        (expect (type-overlap? i64 i64) #t)
        (expect (type-overlap? i64 f64) #f)
        (expect (type-overlap? i64 any-type) #f)
        (expect (type-overlap? any-type i64) #f)
        (expect (type-overlap? i64 a) #t)
        (expect (type-overlap? (list-of i64) (list-of i64)) #t)
        (expect (type-overlap? (list-of i64) (list-of f64)) #f)
        (expect (type-overlap? (list-of i64) (list-of a)) #t)
        (expect (type-overlap? (list-of i64) i64) #f)
        (expect (type-overlap? i64 (code i64 i64)) #f)
        (expect (type-overlap? i64 (Row (Effects (list) (None)))) #f))

      ;; A bare function overlaps anything, and nothing but a variable
      ;; overlaps it; any other callable, one of its own former and
      ;; contract, whatever the arrow; code, code.
      (define (test-callables)
        (let ((dyn-mut (lambda (parameter) (callable (Dyn) (FnMutContract) parameter i64)))
              (impl-fn (callable (Impl) (FnContract) i64 i64)))
          (expect (type-overlap? bare i64) #t)
          (expect (type-overlap? i64 bare) #f)
          (expect (type-overlap? bare (dyn-mut i64)) #t)
          (expect (type-overlap? (dyn-mut i64) bare) #f)
          (expect (type-overlap? bare (callable (Dyn) (FnContract) f64 f64)) #t)
          (expect (type-overlap? (dyn-mut i64) (dyn-mut f64)) #t)
          (expect (type-overlap? (dyn-mut i64) (callable (Dyn) (FnOnceContract) i64 i64)) #f)
          (expect (type-overlap? impl-fn bare) #f)
          (expect (type-overlap? impl-fn (callable (Impl) (FnContract) f64 i64)) #t)
          (expect (type-overlap? (dyn-mut i64) a) #t)
          (expect (type-overlap? (dyn-mut i64) i64) #f)
          (expect (type-overlap? (code i64 i64) (code f64 f64)) #t)
          (expect (type-overlap? (code i64 i64) bare) #f)
          (expect (type-overlap? (code i64 i64) a) #t)
          (expect (type-overlap? (list-of bare) (list-of i64)) #t)
          (expect (type-overlap? (list-of i64) (list-of bare)) #f)))

      ;; A variable overlaps anything, and a repeated one is not unified.
      (define (test-variables)
        (expect (type-overlap? a i64) #t)
        (expect (type-overlap? a (list-of a)) #t)
        (expect (type-overlap? a bare) #t)
        (expect (overlaps? (probe (list a a) 1) (probe (list i64 f64) 2)) #t)
        (expect (overlaps? (probe (list i64 f64) 1) (probe (list a a) 2)) #t)
        (expect (overlaps? (probe (list i64 i64) 1) (probe (list i64 f64) 2)) #f))

      (define store-class (Global main "Store" 0))

      (define (store row type line)
        (instance-of store-class (list (Row (Effects row (None))) type) line (None)))

      (define point
        (Data (Global main "Point" 0)
              (list)
              (list (DataCase (Global main "Point" 0)
                              0
                              (list (DataField "x" #f i64 (list) (at 1)))
                              (list)
                              (at 1)))
              (StructData)
              #f
              #f
              (list)
              (at 1)))

      ;; Instances of one class only, with as many selecting types, each
      ;; overlapping; a row never selects, so two instances for one type
      ;; overlap whatever rows they write (tests/programs/error-class-row-overlap.sld);
      ;; a struct's field instance is an instance of its label's class.
      (define (test-instances)
        (let ((console (Global (list "snail" "core" "io") "console" 0))
              (written-x (ListedInstance (Instance (Global main "x" 4)
                                                   (FieldClass "x")
                                                   (list)
                                                   (list (Con (Global main "Point" 0) (list)) i64)
                                                   (list)
                                                   (list)
                                                   (list)
                                                   (list)
                                                   (at 4))
                                         (None)))
              (implied-x (FieldInstance point (DataField "x" #f i64 (list) (at 1)))))
          (expect (overlaps? (probe (list i64) 1) (instance-of store-class (list i64) 2 (None))) #f)
          (expect (overlaps? (probe (list i64) 1) (probe (list i64 i64) 2)) #f)
          (expect (overlaps? (store (list console) i64 1) (store (list) i64 2)) #t)
          (expect (overlaps? (store (list) i64 1) (store (list) f64 2)) #f)
          (expect (overlaps? written-x implied-x) #t)
          (expect (overlaps? implied-x written-x) #t)
          (expect (overlaps? implied-x (probe (list (Con (Global main "Point" 0) (list)) i64) 2))
                  #f)))

      (define first-set (Global main "first" 0))
      (define second-set (Global main "second" 0))

      ;; Instances active under the sets, in no set or in one of them, are
      ;; paired both ways, but never one with itself, nor two of different
      ;; classes.
      (define (test-active)
        (let ((in-first (instance-of probe-class (list i64) 1 (Some first-set)))
              (in-second (instance-of probe-class (list i64) 2 (Some second-set)))
              (in-none (instance-of probe-class (list a) 3 (None)))
              (other-class (instance-of store-class (list i64) 4 (None))))
          (expect (active-overlap? (list first-set second-set) (list in-first in-second)) #t)
          (expect (active-overlap? (list first-set) (list in-first in-second)) #f)
          (expect (active-overlap? (list) (list in-first in-second)) #f)
          (expect (active-overlap? (list second-set) (list in-none in-second)) #t)
          (expect (active-overlap? (list) (list in-none other-class)) #f)
          (expect (active-overlap? (list) (list in-none)) #f)
          (expect (active-overlap? (list) (list (probe (list bare) 1) (probe (list i64) 2))) #t)
          (expect (active-overlap? (list) (list (probe (list i64) 1) (probe (list bare) 2))) #t)
          (expect (active-overlap? (list) (list (probe (list i64) 1) (probe (list f64) 2))) #f)
          (expect (active-overlap? (list)
                                   (list (probe (list i64) 1)
                                         other-class
                                         (probe (list f64) 3)
                                         (instance-of store-class (list i64) 5 (None))))
                  #t)))))
   (else)))
