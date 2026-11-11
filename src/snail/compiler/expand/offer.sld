;; Offer, the language of what `expand` offers: what a library offers the
;; expansion of each library that imports it. The later passes read the
;; tree, (snail compiler expand language); only another library's
;; expansion, and `derive`, read this.
;;
;;   Offered     ::= Offered library Offer                           no Loc
;;   Expansion   ::= Expansion Expanded Offer                        no Loc
;;
;;   Offer       ::= Offer Export* TopScope                          no Loc
;;   Export      ::= Export name Meaning                             no Loc
;;   TopScope    ::= TopScope Binding* Binding*                      no Loc
;;   Binding     ::= Binding Identifier Meaning                      no Loc
;;   Meaning     ::= Value TopValue | TypeName Global constructs?
;;                 | TypeAlias Global Identifier* Marked library
;;                 | ClassName Global | InstanceSetName Global | Associated Global member
;;                 | EffectName Global | Keyword name | MacroRules Macro
;;                 | ReservedAccessor                                no Loc
;;
;; Marked syntax, Identifier and Macro are (snail compiler expand
;; marked)'s. An offer guarantees that each export means what the
;; library's top level defines or imports under that name, and that the
;; syntax it holds, a macro's rules and an alias's body, resolves in the
;; scopes its marks and its definition name. Each is the top level of a
;; library in the importer's import closure, since a library reaches an
;; importer only through the exports of the libraries it imports. No mark
;; in an offer names a local scope: a mark is made by a use, and a local
;; macro is used only in the body that defines it, which defines no
;; top-level name, so nothing a local macro writes reaches a top level.
(define-library (snail compiler expand offer)
  (export
   Offered
   Expansion
   Offer
   Export
   TopScope
   Bindings
   Binding
   Meaning
   Value
   TypeName
   TypeAlias
   ClassName
   InstanceSetName
   Associated
   EffectName
   Keyword
   MacroRules
   ReservedAccessor)
  (import
   (snail core base)
   (snail core table)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language) Expanded Global TopValue)
   (only (snail compiler expand marked) Marked Identifier Macro))
  (begin

    ;; ---- Expansions ----

    ;; What the integrator hands `expand` for each library an outline's
    ;; imports reach, but (snail core forms), whose offer `expand` knows.
    (struct Offered
      ((library LibraryName)
       (offer Offer)))

    ;; What `expand` writes for one library: the library expanded, and what
    ;; it offers the libraries that import it. Only the integrator keeps
    ;; the offer, to hand to the expansion of each importer.
    (struct Expansion
      ((expanded Expanded)
       (offer Offer)))

    ;; ---- Offers ----

    ;; What a library offers an importer's expansion: what it exports, in
    ;; order, under the names importers know; and its top level, where a
    ;; name its macros and aliases introduce resolves.
    (struct Offer
      ((exports (List Export))
       (scope TopScope)))

    (struct Export
      ((name String)
       (meaning Meaning)))

    ;; A top level's definitions, and the names its import sets give it,
    ;; which a definition of the same name hides.
    (struct TopScope
      ((definitions Bindings)
       (imports Bindings)))

    ;; Each identifier a scope binds, by the name it is written with. Two
    ;; definitions share a name when a macro's template wrote one, which
    ;; marks it.
    (type Bindings (Table (List Binding)))

    (struct Binding
      ((identifier Identifier)
       (meaning Meaning)))

    ;; What a name means at a library's top level. TypeName `constructs?`
    ;; when the type is a struct, whose name is also its constructor. An
    ;; alias and a macro are syntax, each resolving the names it introduces
    ;; where it was defined: an alias's body in the top level of `scope`,
    ;; with each parameter standing for a type, and a macro's rules, read
    ;; only when it is used, at the top level of its id's library.
    ;; ReservedAccessor is `Name-field` for a struct without a mutable
    ;; field, which is read by path instead.
    (enum Meaning
      (Value
       ((value TopValue)))
      (TypeName
       ((global Global)
        (constructs? Bool)))
      (TypeAlias
       ((global Global)
        (parameters (List Identifier))
        (body Marked)
        (scope LibraryName)))
      (ClassName
       ((global Global)))
      (InstanceSetName
       ((global Global)))
      (Associated
       ((class Global)
        (member String)))
      (EffectName
       ((global Global)))
      (Keyword
       ((name String)))
      (MacroRules
       ((macro Macro)))
      (ReservedAccessor))

    ))
