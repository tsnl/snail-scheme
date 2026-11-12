;; What the compiler knows by name of the libraries with a file, as their
;; Globals: the classes of (snail core base) it treats specially, and what
;; of the runtime the code it generates calls and matches, whatever the
;; library it writes in imports.
;;
;; Drop and Clone are the lifecycle classes, whose instances say how a
;; value of their type is dropped and cloned; a Drop instance makes its
;; type's values moved. `declare` checks what a lifecycle instance may be,
;; and `dispatch` dispatches over no lifecycle class.
;;
;; The code `dispatch` writes names what the old compiler names by its
;; unique names (src/snail/shell/compiler/dynamic.sld and
;; conversions.sld): the primitive `any-type-id`, of ("prim"), the
;; identity of what an erased value holds, which a CastError reports;
;; `try-convert`'s answer, `(Ok value)` or an error, and `Pair`, which
;; holds two such answers, matched at once; `conversion-failed`, the
;; control operation of `dyn-cast`, which takes a CastError, its reason
;; UnsupportedInstance or ArgumentMismatch, and never returns; and the
;; List of Strings a CastError's expected types are.
(define-library (snail compiler builtins base)
  (export
   drop-class
   clone-class
   Lifecycle
   Dropping
   Cloning
   instance-lifecycle
   lifecycle-class
   any-type-id-primitive
   ok-case
   pair-case
   cons-case
   nil-case
   cast-error-case
   unsupported-instance-case
   argument-mismatch-case
   conversion-failed-operation
   dyn-cast-effect)
  (import
   (snail core base)
   (snail compiler names libraries)
   (snail compiler names globals))
  (begin

    ;; ---- Lifecycle classes ----

    (: drop-class Global)
    (define drop-class
      (Global base-library "Drop" 0))

    (: clone-class Global)
    (define clone-class
      (Global base-library "Clone" 0))

    ;; Which lifecycle class an instance's class is, if it is one.
    (enum Lifecycle
      (Dropping)
      (Cloning))

    (: instance-lifecycle (impl (Fn ClassRef -> (Option Lifecycle))))
    (define (instance-lifecycle class)
      (match class
        ((ClassGlobal global)
         (cond ((same-global? global drop-class) (Some (Dropping)))
               ((same-global? global clone-class) (Some (Cloning)))
               (else (None))))
        ((FieldClass _) (None))))

    (: lifecycle-class (impl (Fn Lifecycle -> Global)))
    (define (lifecycle-class lifecycle)
      (match lifecycle
        ((Dropping) drop-class)
        ((Cloning) clone-class)))

    ;; ---- The runtime ----

    (: any-type-id-primitive Global)
    (define any-type-id-primitive
      (Global prim-library "any-type-id" 0))

    (: ok-case Global)
    (define ok-case
      (Global base-library "Ok" 0))

    (: pair-case Global)
    (define pair-case
      (Global base-library "Pair" 0))

    (: cons-case Global)
    (define cons-case
      (Global base-library "Cons" 0))

    (: nil-case Global)
    (define nil-case
      (Global base-library "Nil" 0))

    (: cast-error-case Global)
    (define cast-error-case
      (Global base-library "CastError" 0))

    (: unsupported-instance-case Global)
    (define unsupported-instance-case
      (Global base-library "UnsupportedInstance" 0))

    (: argument-mismatch-case Global)
    (define argument-mismatch-case
      (Global base-library "ArgumentMismatch" 0))

    (: conversion-failed-operation Global)
    (define conversion-failed-operation
      (Global base-library "conversion-failed" 0))

    (: dyn-cast-effect Global)
    (define dyn-cast-effect
      (Global base-library "dyn-cast" 0))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-base)
    (import
     (snail stage0 testing))
    (begin
      (define (test-base)
        (expect (map ::name (list drop-class clone-class)) (list "Drop" "Clone"))
        (expect (instance-lifecycle (ClassGlobal drop-class)) (Some (Dropping)))
        (expect (instance-lifecycle (ClassGlobal clone-class)) (Some (Cloning)))
        (expect (instance-lifecycle (ClassGlobal (Global base-library "Show" 0))) (None))
        (expect (instance-lifecycle (ClassGlobal (Global (list "main") "Drop" 0))) (None))
        (expect (instance-lifecycle (FieldClass "x")) (None))
        (expect (map lifecycle-class (list (Dropping) (Cloning))) (list drop-class clone-class)))))
   (else)))
