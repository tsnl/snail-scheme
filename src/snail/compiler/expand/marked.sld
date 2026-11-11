;; Marked syntax, the expander's working language: syntax whose identifiers
;; remember the macro uses that introduced them, and the local frames an
;; identifier is resolved in. `expand` reads a library's body into it,
;; macros write it, and an offer holds a macro's rules and an alias's body
;; in it; no later pass sees it.
;;
;;   Marked      ::= Atom Datum | Ident Identifier | Form Marked*
;;   Identifier  ::= Identifier name Mark*                           no Loc
;;   Mark        ::= Mark library number Scope                       no Loc
;;   Scope       ::= TopLevel library | LocalScope Frame*            no Loc
;;   Frame       ::= Frame Identifier Denotation                     no Loc
;;   Denotation  ::= LocalValue Local | LocalMacro Macro
;;                 | TypeVariable name | TypeArgument index          no Loc
;;   Macro       ::= Macro MacroId Marked* Marked*                   no Loc
;;   MacroId     ::= MacroId library number                          no Loc
;;
;; A mark is one use of a macro, and names the scope the macro was defined
;; in, which holds what it names: the top level of a library, or, for a
;; macro a body defines, the frames from the macro's own frame outward,
;; over the top level of the library being expanded. Those frames are where
;; the macro was defined, with the macro in them, so its template may use
;; it. They are shared structure, and no frame reaches itself, since a
;; macro's rules exist before its frame does. Two marks are one when their
;; libraries and numbers are, whatever scope they name.
(define-library (snail compiler expand marked)
  (export
   Marked
   Atom
   Ident
   Form
   Identifier
   Mark
   Scope
   TopLevel
   LocalScope
   Frame
   Denotation
   LocalValue
   LocalMacro
   TypeVariable
   TypeArgument
   Macro
   MacroId)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler read language) Datum)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler expand language) Local))
  (begin

    ;; ---- Syntax ----

    ;; A node a template introduces is at the macro's use; an atom stays
    ;; where the template writes it.
    (enum Marked
      (Atom
       ((datum Datum)
        (loc Loc)))
      (Ident
       ((identifier Identifier)
        (loc Loc)))
      (Form
       ((items (List Marked))
        (loc Loc))))

    ;; A name, and the marks of the macro uses that introduced it, the
    ;; latest first. Two identifiers are one when their names and marks
    ;; are; one that nothing binds where it is used resolves without its
    ;; latest mark, in that mark's scope.
    (struct Identifier
      ((name String)
       (marks (List Mark))))

    ;; One use of a macro: the library whose expansion used it, numbered
    ;; within that library, and the scope the macro was defined in.
    (struct Mark
      ((library LibraryName)
       (number I64)
       (scope Scope)))

    (enum Scope
      (TopLevel
       ((library LibraryName)))
      (LocalScope
       ((frames (List Frame)))))

    ;; ---- Frames ----

    ;; One identifier a local form binds, and what it binds it to.
    (struct Frame
      ((identifier Identifier)
       (denotation Denotation)))

    ;; What a frame binds: a local variable; a macro a body defines; a type
    ;; variable a scheme, declaration or instance binds, known by its name;
    ;; or an alias's parameter, which stands for the type its use gives at
    ;; `index`, counting from 0.
    (enum Denotation
      (LocalValue
       ((local Local)))
      (LocalMacro
       ((macro Macro)))
      (TypeVariable
       ((name String)))
      (TypeArgument
       ((index I64))))

    ;; ---- Macros ----

    ;; A `syntax-rules` macro: its literals and rules as written. Where its
    ;; templates' names resolve is where it was found: a top-level macro's
    ;; at the top level of the library its id names, a local macro's in the
    ;; frames from its own outward.
    (struct Macro
      ((id MacroId)
       (literals (List Marked))
       (rules (List Marked))))

    ;; Two macros are one when their ids are: the library that defines
    ;; one, and its number there.
    (struct MacroId
      ((library LibraryName)
       (number I64)))

    ))
