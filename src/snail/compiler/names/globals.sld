;; The names a tree holds once `expand` has resolved it, which every pass
;; after it carries: a Global, what a library's top level defines; a
;; Local, what a binder binds; a TopValue, a Global or one of the functions
;; a field declares; a ClassRef, a declared class or the field class of a
;; label; and a Label, the one name `expand` leaves unresolved, for the
;; pass that has the declaration it names.
;;
;; A name is data. Two are the same when their parts are, and no pass
;; builds one by joining text or reads one by scanning it. Globals have
;; one order, by library, then name, then serial, which makes a set of
;; them, such as a row's effects, one list.
(define-library (snail compiler names globals)
  (export
   Global
   Local
   TopValue
   TopGlobal
   FieldFunction
   FieldRole
   Accessor
   Replacer
   Setter
   Swapper
   ClassRef
   ClassGlobal
   FieldClass
   Label
   same-global?
   global<?
   same-top-value?)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries))
  (begin

    ;; ---- Names ----

    ;; A value, type, class, effect or instance set a library's top level
    ;; defines. `serial` is 0 for a name the library writes; a name a
    ;; macro's template wrote has a serial of its own, unique in the
    ;; library, since two expansions may write it, and so does a Global a
    ;; later pass writes, numbered as (snail compiler names numbering)
    ;; says.
    (struct Global
      ((library LibraryName)
       (name String)
       (serial I64)))

    ;; A local is the name written at its binder, numbered within the
    ;; library, so two locals are one when their numbers are.
    (struct Local
      ((name String)
       (number I64)))

    ;; A top-level value: a Global, or one of the functions a field of the
    ;; case whose constructor is `case` declares. An enum case's field has
    ;; an Accessor, `Case-field`; a struct's mutable field an Accessor, a
    ;; Setter and a Swapper, `Name-field`, `Name-field-set!` and
    ;; `Name-field-replace!`; and a field of a struct without one a
    ;; Replacer, `Name-field-set`.
    (enum TopValue
      (TopGlobal
       ((global Global)))
      (FieldFunction
       ((case Global)
        (label String)
        (role FieldRole))))

    (enum FieldRole
      (Accessor)
      (Replacer)
      (Setter)
      (Swapper))

    ;; A declared class, or the field class of a label, written `::label`,
    ;; which every label has.
    (enum ClassRef
      (ClassGlobal
       ((global Global)))
      (FieldClass
       ((label String))))

    ;; A member's name as written, where it is written.
    (struct Label
      ((name String)
       (loc Loc)))

    ;; ---- Sameness and order ----

    (: same-global? (impl (Fn Global Global -> Bool)))
    (define (same-global? global other)
      (and (same-library? (::library global) (::library other))
           (string=? (::name global) (::name other))
           (= (::serial global) (::serial other))))

    ;; Globals in order: by library, then by name, then by serial.
    (: global<? (impl (Fn Global Global -> Bool)))
    (define (global<? global other)
      (cond ((library<? (::library global) (::library other)) #t)
            ((library<? (::library other) (::library global)) #f)
            ((string<? (::name global) (::name other)) #t)
            ((string<? (::name other) (::name global)) #f)
            (else (< (::serial global) (::serial other)))))

    (: same-top-value? (impl (Fn TopValue TopValue -> Bool)))
    (define (same-top-value? value other)
      (match (Pair value other)
        ((Pair (TopGlobal global) (TopGlobal other-global)) (same-global? global other-global))
        ((Pair (FieldFunction case label role) (FieldFunction other-case other-label other-role))
         (and (same-global? case other-case)
              (string=? label other-label)
              (same-role? role other-role)))
        (_ #f)))

    (: same-role? (impl (Fn FieldRole FieldRole -> Bool)))
    (define (same-role? role other)
      (match (Pair role other)
        ((Pair (Accessor) (Accessor)) #t)
        ((Pair (Replacer) (Replacer)) #t)
        ((Pair (Setter) (Setter)) #t)
        ((Pair (Swapper) (Swapper)) #t)
        (_ #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-globals)
    (import
     (snail stage0 testing))
    (begin
      (define (test-globals)
        (test-same)
        (test-order))

      (define main (list "main"))

      ;; A Global by its library, name and serial; a field function by its
      ;; case, label and role too.
      (define (test-same)
        (let ((point (Global main "Point" 0)))
          (expect (same-global? point (Global main "Point" 0)) #t)
          (expect (same-global? point (Global main "Point" 1)) #f)
          (expect (same-global? point (Global (list "a") "Point" 0)) #f)
          (expect (same-top-value? (TopGlobal point) (TopGlobal (Global main "Point" 0))) #t)
          (expect (same-top-value? (FieldFunction point "x" (Accessor))
                                   (FieldFunction point "x" (Accessor)))
                  #t)
          (expect (same-top-value? (FieldFunction point "x" (Accessor))
                                   (FieldFunction point "x" (Replacer)))
                  #f)
          (expect (same-top-value? (FieldFunction point "x" (Accessor))
                                   (FieldFunction point "y" (Accessor)))
                  #f)
          (expect (same-top-value? (TopGlobal point) (FieldFunction point "x" (Accessor))) #f)))

      ;; By library, then name, then serial; a library before any longer
      ;; one it begins.
      (define (test-order)
        (let ((io (Global main "io" 0)))
          (expect (global<? (Global (list "a") "z" 0) (Global (list "b") "a" 0)) #t)
          (expect (global<? (Global (list "a") "x" 0) (Global (list "a" "b") "a" 0)) #t)
          (expect (global<? (Global (list "a" "b") "a" 0) (Global (list "a") "x" 0)) #f)
          (expect (global<? (Global (list "a") "x" 0) (Global (list "a") "y" 0)) #t)
          (expect (global<? (Global (list "a") "x" 2) (Global (list "a") "x" 1)) #f)
          (expect (global<? (Global (list "a") "x" 1) (Global (list "a") "x" 2)) #t)
          (expect (global<? io io) #f)))))
   (else)))
