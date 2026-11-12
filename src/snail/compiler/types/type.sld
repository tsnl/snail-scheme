;; What a type is, as every pass from `declare` on holds it: a value, with
;; no Loc, compared and substituted as values are.
;;
;;   Type         ::= Con Global Type* | Callable Former Contract Arrow | Code Arrow
;;                  | Row Effects | Var TypeVariable
;;   Arrow        ::= Arrow Type* Type Effects
;;   Effects      ::= Effects Global* Type?
;;   TypeVariable ::= Written name | Associated number label
;;                  | CallableArgument number | Own TypeVariable
;;   Former       ::= Impl | Dyn
;;   Contract     ::= FnContract | FnMutContract | FnOnceContract
;;
;; A Con is a declared type or a builtin of (snail core forms), at its
;; arguments. A row's labels are a set: each effect once, in the order of
;; their Globals, (snail compiler names globals). Its tail, when it has
;; one, is what the row was written to end with, kept as written, which
;; may be a row itself or any other type. So two rows with the same labels
;; and the same tail are the same value, and a row whose tail is a row is
;; not the same value as the one row they make. Former and Contract are
;; Expanded's too, since a written callable type names them.
(define-library (snail compiler types type)
  (export
   Type
   Con
   Callable
   Code
   Row
   Var
   Arrow
   Effects
   TypeVariable
   Written
   Associated
   CallableArgument
   Own
   Former
   Impl
   Dyn
   Contract
   FnContract
   FnMutContract
   FnOnceContract)
  (import
   (snail core base)
   (only (snail compiler names globals) Global))
  (begin

    ;; ---- Types ----

    ;; A declared or builtin type at its arguments. `(impl (Fn ...))` and
    ;; `(dyn (FnMut ...))` are Callables; `(dyn (Fn ...))` is a Callable
    ;; too, which the old compiler writes as its bare arrow. `(fn ...)` is
    ;; Code. A Row is `(! effect ... tail)` as a type argument, as `e` in
    ;; `(Store (! io) S)`.
    (enum Type
      (Con
       ((type Global)
        (arguments (List Type))))
      (Callable
       ((former Former)
        (contract Contract)
        (arrow Arrow)))
      (Code
       ((arrow Arrow)))
      (Row
       ((effects Effects)))
      (Var
       ((variable TypeVariable))))

    (struct Arrow
      ((parameters (List Type))
       (result Type)
       (effects Effects)))

    ;; A set of effects, each once, in the order of their Globals, and the
    ;; type the row ends with, as written.
    (struct Effects
      ((labels (List Global))
       (tail (Option Type))))

    ;; ---- Variables ----

    ;; A variable the source names; an output the requirement at position
    ;; `number` of the scheme that introduces it leaves unwritten; the type
    ;; the caller chooses for an `impl` parameter, the variable at position
    ;; `number` of the scheme that introduces it; or, in the scheme of an
    ;; instance's implementation of a method, one of the method's own
    ;; variables, kept apart from the instance's. None is ever a name the
    ;; compiler joined.
    (enum TypeVariable
      (Written
       ((name String)))
      (Associated
       ((number I64)
        (label String)))
      (CallableArgument
       ((number I64)))
      (Own
       ((variable TypeVariable))))

    ;; ---- Callables ----

    ;; `impl`, a callable the caller chooses, or `dyn`, one erased behind
    ;; its arrow.
    (enum Former
      (Impl)
      (Dyn))

    ;; How often a callable may be called: any number of times without
    ;; mutating what it holds, any number of times mutating it, or once.
    (enum Contract
      (FnContract)
      (FnMutContract)
      (FnOnceContract))

    ))
