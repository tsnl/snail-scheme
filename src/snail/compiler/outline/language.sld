;; Outline, the language `outline` writes: a file's header parsed, and its
;; body still Syntax.
;;
;;   Outline    ::= Written Library                    no Loc
;;                | Generated library Syntax* Syntax    the recipe's imports and expression
;;   Library    ::= Defined library Import* Export* Syntax*
;;                | Program key* recipe? Import* Syntax*  no Loc
;;   Import     ::= Whole library | Only Import Identifier* | Except Import Identifier*
;;                | Prefix Import prefix | Rename Import Renaming*
;;   Renaming   ::= Renaming Identifier name            no Loc but its identifier's
;;   Export     ::= Export Identifier name              no Loc but its identifier's
;;   Identifier ::= Identifier name
;;
;; Over the Syntax it comes from, an Outline guarantees that a library's
;; file holds one library, under the name it was found by; that its
;; declarations are joined into imports, exports and body, each in the
;; order written, with every `cond-expand` decided; and that every import
;; set and export is well formed. A library name is its parts in order,
;; with an integer part as its decimal text. A Library is what `expand`
;; takes: a file with a body, written by hand or printed by a producer. A
;; generated library is not one, since its body is what its producer will
;; print; the integrator outlines that output as a Library before anything
;; expands it. A program has no form of its own, so it carries no Loc. Its keys are the libraries loading when a
;; producer program was printed, as its `generating` form wrote them, and
;; its recipe the file a producer's `recipe` form names. Nothing in a body
;; is read, nor a generated library's imports or expression, which become
;; a producer program's.
(define-library (snail compiler outline language)
  (export
   LibraryName
   Outline
   Written
   Generated
   Library
   Defined
   Program
   Import
   Whole
   Only
   Except
   Prefix
   Rename
   Renaming
   Export
   Identifier)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler read language))
  (begin

    ;; ---- Libraries ----

    ;; `(snail core base)` is ("snail" "core" "base").
    (type LibraryName (List String))

    ;; A file outlined: a library or program with a body to expand, or a
    ;; generated library, at its `generate-library` form.
    (enum Outline
      (Written
       ((library Library)))
      (Generated
       ((name LibraryName)
        (imports (List Syntax))
        (expression Syntax)
        (loc Loc))))

    ;; A library is at its `define-library` form.
    (enum Library
      (Defined
        ((name LibraryName)
         (imports (List Import))
         (exports (List Export))
         (body (List Syntax))
         (loc Loc)))
      (Program
       ((loading (List String))
        (recipe (Option String))
        (imports (List Import))
        (body (List Syntax)))))

    ;; ---- Imports ----

    ;; An import set is at its form: a library at its name, and a modifier
    ;; at the form around the set it modifies.
    (enum Import
      (Whole
       ((library LibraryName)
        (loc Loc)))
      (Only
       ((inner Import)
        (names (List Identifier))
        (loc Loc)))
      (Except
       ((inner Import)
        (names (List Identifier))
        (loc Loc)))
      (Prefix
       ((inner Import)
        (prefix String)
        (loc Loc)))
      (Rename
       ((inner Import)
        (renamings (List Renaming))
        (loc Loc))))

    ;; An identifier of the library, and the name it is imported as.
    (struct Renaming
      ((identifier Identifier)
       (name String)))

    ;; ---- Exports ----

    ;; An identifier of the library, and the name importers know it by:
    ;; its own unless a `rename` gives another.
    (struct Export
      ((identifier Identifier)
       (name String)))

    ;; ---- Identifiers ----

    ;; A name as written, where it is written.
    (struct Identifier
      ((name String)
       (loc Loc)))

    ))
