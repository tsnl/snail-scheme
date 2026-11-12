;; What the code `dispatch` writes names of the runtime: the Globals of
;; (snail core base), ("prim") and (snail core forms) its lambdas call and
;; match, which the old compiler names by their unique names
;; (src/snail/shell/compiler/dynamic.sld and conversions.sld) whatever the
;; library imports, as `dispatch` names them.
;;
;; - `Any` is the type every erased value has, and `any-type-id` the
;;   identity of what one holds, which a CastError reports.
;; - `try-convert` answers `(Ok value)` or an error; `Pair` holds two
;;   such answers, matched at once.
;; - `conversion-failed`, the control operation of `dyn-cast`, takes a
;;   CastError, its reason UnsupportedInstance or ArgumentMismatch, and
;;   never returns. A CastError's expected types are a List of Strings.
(define-library (snail compiler dispatch runtime)
  (export
   any-type
   any-type?
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
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language) Global)
   (only (snail compiler declare language) Type Con)
   (only (snail compiler declare forms) forms-library)
   (only (snail compiler declare equality) same-global?))
  (begin

    ;; ---- Any ----

    (: any-global Global)
    (define any-global
      (Global forms-library "Any" 0))

    (: any-type Type)
    (define any-type
      (Con any-global (Nil)))

    (: any-type? (impl (Fn Type -> Bool)))
    (define (any-type? type)
      (match type
        ((Con global (Nil)) (same-global? global any-global))
        (_ #f)))

    (: any-type-id-primitive Global)
    (define any-type-id-primitive
      (Global (list "prim") "any-type-id" 0))

    ;; ---- (snail core base) ----

    (: base-library LibraryName)
    (define base-library
      (list "snail" "core" "base"))

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
     test-runtime)
    (import
     (snail stage0 testing))
    (begin
      (define (test-runtime)
        (expect (any-type? any-type) #t)
        (expect (any-type? (Con (Global forms-library "I64" 0) (list))) #f)
        (expect (any-type? (Con (Global (list "main") "Any" 0) (list))) #f)
        (expect (any-type? (Con any-global (list any-type))) #f))))
   (else)))
