;; Declarations, the other language `declare` writes: what a declared
;; library offers the declaration of each library whose import closure
;; holds it. The later passes read the tree, (snail compiler declare
;; language); only another library's `declare`, and the passes that need a
;; declaration's content as `declare` left it (`dispatch`, the adapter),
;; read this.
;;
;;   DeclaredLibrary ::= DeclaredLibrary Declared Declarations       no Loc
;;   Declarations ::= Declarations library Data* Class* Effect*      no Loc
;;   Effect       ::= OfferedEffect Global Operation*                no Loc
;;
;; Data, Class and Operation are Declared's, the same values the tree
;; holds. An offered effect is its operations alone: no importer reads a
;; default, and an offer holds no expression.
;;
;; An offer guarantees that it holds every data type, class and effect the
;; library declares, complete: a data type says whether its library
;; declares a Drop instance for it, which no other library can, and a
;; class which of its parameters are rows. It holds no instance: an
;; instance is global, and the passes that choose or compare instances
;; are handed every instance of the libraries before, not offers. It holds
;; no value's scheme but a method's and an operation's: a definition's
;; scheme is `infer`'s to offer, and a constructor's and a field
;; function's follow from its data type.
;;
;; Each kind is kept by name, a list for the Globals that share one when
;; a macro's template wrote them, as expand's offer keeps its bindings, so
;; a lookup is a table's and then a serial's.
(define-library (snail compiler declare offer)
  (export
   DeclaredLibrary
   Declarations
   OfferedEffect)
  (import
   (snail core base)
   (snail core table)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language) Global)
   (only (snail compiler declare language) Declared Data Class Operation))
  (begin

    ;; What `declare` writes for one library: the library declared, and
    ;; what it offers. Only the integrator keeps the offer, to hand to the
    ;; declaration of each library whose import closure holds this one.
    (struct DeclaredLibrary
      ((declared Declared)
       (declarations Declarations)))

    (struct Declarations
      ((library LibraryName)
       (data (Table (List Data)))
       (classes (Table (List Class)))
       (effects (Table (List OfferedEffect)))))

    (struct OfferedEffect
      ((global Global)
       (operations (List Operation))))

    ))
