;; When two Globals, and two types, are the same; and the one order of a
;; row's effects, which makes the same set of effects the same list. A
;; type is a value, so two types are the same exactly when they are equal
;; part by part: a row's labels are compared as the lists they are, which
;; the order makes the sets they stand for, and its tail as written, as
;; the old compiler's `type=?` compares a row's.
(define-library (snail compiler declare equality)
  (export
   same-global?
   global<?
   effect-set
   same-type?
   same-types?
   same-variable?
   variable-among?)
  (import
   (snail core base)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler outline names) same-library?)
   (only (snail compiler expand language)
         Global
         Former
         Impl
         Dyn
         Contract
         FnContract
         FnMutContract
         FnOnceContract)
   (snail compiler declare language))
  (begin

    ;; ---- Globals ----

    (: same-global? (impl (Fn Global Global -> Bool)))
    (define (same-global? global other)
      (and (same-library? (::library global) (::library other))
           (string=? (::name global) (::name other))
           (= (::serial global) (::serial other))))

    ;; Globals in order: by library, its parts compared in turn, a name
    ;; before any longer name it begins; then by name; then by serial.
    (: global<? (impl (Fn Global Global -> Bool)))
    (define (global<? global other)
      (cond ((library<? (::library global) (::library other)) #t)
            ((library<? (::library other) (::library global)) #f)
            ((string<? (::name global) (::name other)) #t)
            ((string<? (::name other) (::name global)) #f)
            (else (< (::serial global) (::serial other)))))

    (: library<? (impl (Fn LibraryName LibraryName -> Bool)))
    (define (library<? name other)
      (match (Pair name other)
        ((Pair (Nil) (Nil)) #f)
        ((Pair (Nil) _) #t)
        ((Pair _ (Nil)) #f)
        ((Pair (Cons part rest) (Cons other-part other-rest))
         (cond ((string<? part other-part) #t)
               ((string<? other-part part) #f)
               (else (library<? rest other-rest))))))

    ;; ---- Effects ----

    ;; The effects a row writes as a set: each once, in order.
    (: effect-set (impl (Fn (List Global) -> (List Global))))
    (define (effect-set labels)
      (fold-left (lambda (set label) (with-effect label set)) (Nil) labels))

    (: with-effect (impl (Fn Global (List Global) -> (List Global))))
    (define (with-effect label set)
      (match set
        ((Nil) (list label))
        ((Cons first rest)
         (cond ((same-global? label first) set)
               ((global<? label first) (Cons label set))
               (else (Cons first (with-effect label rest)))))))

    ;; ---- Types ----

    (: same-type? (impl (Fn Type Type -> Bool)))
    (define (same-type? type other)
      (match (Pair type other)
        ((Pair (Con global arguments) (Con other-global others))
         (and (same-global? global other-global) (same-types? arguments others)))
        ((Pair (Callable former contract arrow) (Callable other-former other-contract other-arrow))
         (and (same-former? former other-former)
              (same-contract? contract other-contract)
              (same-arrow? arrow other-arrow)))
        ((Pair (Code arrow) (Code other-arrow)) (same-arrow? arrow other-arrow))
        ((Pair (Row effects) (Row other-effects)) (same-effects? effects other-effects))
        ((Pair (Var variable) (Var other-variable)) (same-variable? variable other-variable))
        (_ #f)))

    (: same-types? (impl (Fn (List Type) (List Type) -> Bool)))
    (define (same-types? types others)
      (and (= (length types) (length others))
           (every? (lambda (pair) (same-type? (::first pair) (::second pair))) (zip types others))))

    (: same-arrow? (impl (Fn Arrow Arrow -> Bool)))
    (define (same-arrow? arrow other)
      (and (same-types? (::parameters arrow) (::parameters other))
           (same-type? (::result arrow) (::result other))
           (same-effects? (::effects arrow) (::effects other))))

    (: same-effects? (impl (Fn Effects Effects -> Bool)))
    (define (same-effects? effects other)
      (and (= (length (::labels effects)) (length (::labels other)))
           (every? (lambda (pair) (same-global? (::first pair) (::second pair)))
                   (zip (::labels effects) (::labels other)))
           (match (Pair (::tail effects) (::tail other))
             ((Pair (Some tail) (Some other-tail)) (same-type? tail other-tail))
             ((Pair (None) (None)) #t)
             (_ #f))))

    (: same-variable? (impl (Fn TypeVariable TypeVariable -> Bool)))
    (define (same-variable? variable other)
      (match (Pair variable other)
        ((Pair (Written name) (Written other-name)) (string=? name other-name))
        ((Pair (Associated number label) (Associated other-number other-label))
         (and (= number other-number) (string=? label other-label)))
        ((Pair (CallableArgument number) (CallableArgument other-number)) (= number other-number))
        ((Pair (Own inner) (Own other-inner)) (same-variable? inner other-inner))
        (_ #f)))

    (: variable-among? (impl (Fn TypeVariable (List TypeVariable) -> Bool)))
    (define (variable-among? variable variables)
      (any? (lambda (other) (same-variable? other variable)) variables))

    (: same-former? (impl (Fn Former Former -> Bool)))
    (define (same-former? former other)
      (match (Pair former other)
        ((Pair (Impl) (Impl)) #t)
        ((Pair (Dyn) (Dyn)) #t)
        (_ #f)))

    (: same-contract? (impl (Fn Contract Contract -> Bool)))
    (define (same-contract? contract other)
      (match (Pair contract other)
        ((Pair (FnContract) (FnContract)) #t)
        ((Pair (FnMutContract) (FnMutContract)) #t)
        ((Pair (FnOnceContract) (FnOnceContract)) #t)
        (_ #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-equality)
    (import
     (snail stage0 testing))
    (begin
      (define (test-equality)
        (test-order)
        (test-effect-sets)
        (test-types))

      (define (global library name serial)
        (Global library name serial))

      (define io (global (list "main") "io" 0))
      (define log (global (list "main") "log" 0))
      (define mut (global (list "snail" "core" "forms") "mut" 0))

      ;; By library, then name, then serial; a library before any longer
      ;; one it begins.
      (define (test-order)
        (expect (global<? (global (list "a") "z" 0) (global (list "b") "a" 0)) #t)
        (expect (global<? (global (list "a") "x" 0) (global (list "a" "b") "a" 0)) #t)
        (expect (global<? (global (list "a" "b") "a" 0) (global (list "a") "x" 0)) #f)
        (expect (global<? (global (list "a") "x" 0) (global (list "a") "y" 0)) #t)
        (expect (global<? (global (list "a") "x" 2) (global (list "a") "x" 1)) #f)
        (expect (global<? (global (list "a") "x" 1) (global (list "a") "x" 2)) #t)
        (expect (global<? io io) #f)
        (expect (same-global? io (global (list "main") "io" 0)) #t)
        (expect (same-global? io (global (list "main") "io" 1)) #f))

      ;; Each effect once, in order, whatever order the row wrote.
      (define (test-effect-sets)
        (expect (effect-set (list)) (list))
        (expect (effect-set (list mut log io log)) (list io log mut))
        (expect (effect-set (list io log)) (effect-set (list log io io))))

      ;; Rows by their sets and their tails as written.
      (define (test-types)
        (let ((a (Var (Written "a")))
              (closed (lambda (labels) (Row (Effects labels (None))))))
          (expect (same-type? (Con io (list a)) (Con io (list a))) #t)
          (expect (same-type? (Con io (list a)) (Con io (list (Var (Written "b"))))) #f)
          (expect (same-type? (Con io (list)) (Con log (list))) #f)
          (expect
           (same-type? (closed (effect-set (list io log))) (closed (effect-set (list log io))))
           #t)
          (expect (same-type? (closed (list io)) (Row (Effects (list io) (Some a)))) #f)
          ;; A row ending with a row is not the one row they make.
          (expect (same-type? (Row (Effects (list io) (Some (closed (list log)))))
                              (closed (effect-set (list io log))))
                  #f)
          (expect (same-type? (Var (Associated 0 "Out")) (Var (Associated 0 "Out"))) #t)
          (expect (same-type? (Var (Associated 0 "Out")) (Var (Associated 1 "Out"))) #f)
          (expect (same-type? (Var (CallableArgument 2)) (Var (Written "a"))) #f)
          (expect
           (same-type? (Callable (Dyn) (FnContract) (Arrow (list a) a (Effects (list) (None))))
                       (Callable (Dyn) (FnMutContract) (Arrow (list a) a (Effects (list) (None)))))
           #f)
          (expect (same-type? (Code (Arrow (list) a (Effects (list io) (None))))
                              (Code (Arrow (list) a (Effects (list io) (None)))))
                  #t)
          (expect (variable-among? (Written "a") (list (Associated 0 "a") (Written "a"))) #t)
          (expect (variable-among? (Written "a") (list (Own (Written "a")))) #f)))))
   (else)))
