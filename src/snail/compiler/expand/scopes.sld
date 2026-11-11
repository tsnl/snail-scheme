;; What an identifier means where it is used: the rule hygiene rests on.
;; An identifier is looked up in the local frames around it, then at the
;; top level they sit over, where a definition hides an import. One that
;; nothing binds there, if a macro's template introduced it, means what it
;; meant where that macro was defined: its latest mark is dropped and it is
;; looked up again in the mark's scope. So a template's free names mean
;; what they meant at its definition, and a name it binds binds only what
;; the same expansion wrote, since a use's identifiers have no such mark.
;;
;; The rule loops over an identifier's frames and marks, and walks no
;; program. It is handed every top level a mark can name, as `Scopes`: the
;; library being expanded, its top level as bound so far, and the offer of
;; each library its imports reach. The offers suffice: a top-level macro's
;; scope is the top level of the library defining it, which reached this
;; one through the exports of the libraries it imports. A local macro's
;; scope is the frames it was found in, which a mark holds, so nothing
;; about a body is stored here.
(define-library (snail compiler expand scopes)
  (export
   Env
   Scopes
   Resolution
   Unbound
   BoundLocally
   BoundAtTop
   resolve
   head-resolution
   MacroAt
   resolved-macro
   scope-env
   offer-of
   written
   marked-loc
   same-global?
   same-top-value?
   same-identifier?
   same-meaning?
   same-resolution?)
  (import
   (snail core base)
   (snail core table)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (only (snail compiler outline language) LibraryName)
   (only (snail compiler outline names) same-library?)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer))
  (begin

    ;; ---- Environments ----

    ;; Where an identifier is expanded: the local frames around it,
    ;; innermost first, over the top level of `library`.
    (struct Env
      ((frames (List Frame))
       (library LibraryName)))

    ;; Every top level a mark can name. `top` is the library's own as the
    ;; expansion has bound it so far, and `offers` holds the offer of every
    ;; library the library's imports reach, (snail core forms)'s among them.
    (struct Scopes
      ((library LibraryName)
       (top TopScope)
       (offers (List Offered))))

    ;; ---- Resolution ----

    ;; A frame's binding carries its home: the frames from the binding one
    ;; outward, which is the environment its binder made.
    (enum Resolution
      (Unbound)
      (BoundLocally
       ((denotation Denotation)
        (home (List Frame))))
      (BoundAtTop
       ((meaning Meaning))))

    (: resolve (impl (Fn Scopes Env Identifier -> Resolution)))
    (define (resolve scopes env identifier)
      (match (framed (::frames env) identifier)
        ((Some home) (BoundLocally (::denotation (home-frame home)) home))
        ((None)
         (match (top-meaning (top-scope scopes (::library env)) identifier)
           ((Some meaning) (BoundAtTop meaning))
           ((None) (introduced scopes identifier))))))

    ;; An identifier nothing binds where it is used: unbound if it was
    ;; written there, and else what it means without its latest mark, in
    ;; that mark's scope.
    (: introduced (impl (Fn Scopes Identifier -> Resolution)))
    (define (introduced scopes identifier)
      (match (::marks identifier)
        ((Nil) (Unbound))
        ((Cons mark earlier)
         (resolve scopes
                  (scope-env scopes (::scope mark))
                  (Identifier (::name identifier) earlier)))))

    ;; The frames from the innermost one binding `identifier` outward.
    (: framed (impl (Fn (List Frame) Identifier -> (Option (List Frame)))))
    (define (framed frames identifier)
      (match frames
        ((Nil) (None))
        ((Cons frame outer)
         (if (same-identifier? (::identifier frame) identifier)
             (Some frames)
             (framed outer identifier)))))

    (: home-frame (impl (Fn (List Frame) -> Frame)))
    (define (home-frame home)
      (match home
        ((Cons frame _) frame)
        ((Nil) (panic "internal error: a home without its frame"))))

    (: top-meaning (impl (Fn TopScope Identifier -> (Option Meaning))))
    (define (top-meaning top identifier)
      (match (bound-meaning (::definitions top) identifier)
        ((Some meaning) (Some meaning))
        ((None) (bound-meaning (::imports top) identifier))))

    (: bound-meaning (impl (Fn Bindings Identifier -> (Option Meaning))))
    (define (bound-meaning bindings identifier)
      (match (table-ref bindings (::name identifier))
        ((Some candidates)
         (match (find (lambda (binding) (same-identifier? (::identifier binding) identifier))
                      candidates)
           ((Some binding) (Some (::meaning binding)))
           ((None) (None))))
        ((None) (None))))

    ;; ---- Heads and macros ----

    ;; What the identifier at a form's head means, if one is there.
    (: head-resolution (impl (Fn Scopes Env Marked -> Resolution)))
    (define (head-resolution scopes env syntax)
      (match syntax
        ((Form (Cons (Ident identifier _) _) _) (resolve scopes env identifier))
        (_ (Unbound))))

    ;; A macro a name resolves to, and the scope its templates' names
    ;; resolve in, which the marks of its uses name.
    (struct MacroAt
      ((macro Macro)
       (home Scope)))

    (: resolved-macro (impl (Fn Resolution -> (Option MacroAt))))
    (define (resolved-macro resolution)
      (match resolution
        ((BoundAtTop (MacroRules macro)) (Some (MacroAt macro (TopLevel (::library (::id macro))))))
        ((BoundLocally (LocalMacro macro) home) (Some (MacroAt macro (LocalScope home))))
        (_ (None))))

    ;; ---- Scopes ----

    ;; The environment a scope names: a top level with no frames over it,
    ;; or a local macro's frames, over the library being expanded, where
    ;; every local macro is used.
    (: scope-env (impl (Fn Scopes Scope -> Env)))
    (define (scope-env scopes scope)
      (match scope
        ((TopLevel library) (Env (Nil) library))
        ((LocalScope frames) (Env frames (::library scopes)))))

    (: top-scope (impl (Fn Scopes LibraryName -> TopScope)))
    (define (top-scope scopes library)
      (if (same-library? library (::library scopes))
          (::top scopes)
          (::scope (offer-of (::offers scopes) library))))

    ;; The offer of a library in the import closure. Every library a scope
    ;; or an import set names is there, as the header says, and the
    ;; integrator expands a library only after every library it imports.
    (: offer-of (impl (Fn (List Offered) LibraryName -> Offer)))
    (define (offer-of offers library)
      (match (find (lambda (offered) (same-library? (::library offered) library)) offers)
        ((Some offered) (::offer offered))
        ((None) (panic "internal error: a library outside the import closure"))))

    ;; ---- Written syntax ----

    ;; Syntax as the source writes it, which no macro introduced.
    (: written (impl (Fn syntax-Syntax -> Marked)))
    (define (written syntax)
      (match syntax
        ((syntax-Atom datum loc) (Atom datum loc))
        ((syntax-Ident name loc) (Ident (Identifier name (Nil)) loc))
        ((syntax-Form items loc) (Form (map written items) loc))))

    (: marked-loc (impl (Fn Marked -> Loc)))
    (define (marked-loc syntax)
      (match syntax
        ((Atom _ loc) loc)
        ((Ident _ loc) loc)
        ((Form _ loc) loc)))

    ;; ---- Identity ----

    ;; Two identifiers are one when their names and marks are, and two
    ;; marks when their libraries and numbers are.
    (: same-identifier? (impl (Fn Identifier Identifier -> Bool)))
    (define (same-identifier? identifier other)
      (and (string=? (::name identifier) (::name other))
           (same-marks? (::marks identifier) (::marks other))))

    (: same-marks? (impl (Fn (List Mark) (List Mark) -> Bool)))
    (define (same-marks? marks others)
      (match (Pair marks others)
        ((Pair (Nil) (Nil)) #t)
        ((Pair (Cons mark rest) (Cons other more))
         (and (same-library? (::library mark) (::library other))
              (= (::number mark) (::number other))
              (same-marks? rest more)))
        (_ #f)))

    (: same-global? (impl (Fn Global Global -> Bool)))
    (define (same-global? global other)
      (and (same-library? (::library global) (::library other))
           (string=? (::name global) (::name other))
           (= (::serial global) (::serial other))))

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

    ;; Two meanings are the same when they denote the same declaration,
    ;; which is when two imports of one name do not conflict, and when a
    ;; macro's literal matches. Every reserved accessor is one, as the old
    ;; expander binds them all to one piece of syntax.
    (: same-meaning? (impl (Fn Meaning Meaning -> Bool)))
    (define (same-meaning? meaning other)
      (match (Pair meaning other)
        ((Pair (Value value) (Value other-value)) (same-top-value? value other-value))
        ((Pair (TypeName global _) (TypeName other-global _)) (same-global? global other-global))
        ((Pair (TypeAlias global _ _ _) (TypeAlias other-global _ _ _))
         (same-global? global other-global))
        ((Pair (ClassName global) (ClassName other-global)) (same-global? global other-global))
        ((Pair (InstanceSetName global) (InstanceSetName other-global))
         (same-global? global other-global))
        ((Pair (Associated class member) (Associated other-class other-member))
         (and (same-global? class other-class) (string=? member other-member)))
        ((Pair (EffectName global) (EffectName other-global)) (same-global? global other-global))
        ((Pair (Keyword name) (Keyword other-name)) (string=? name other-name))
        ((Pair (MacroRules macro) (MacroRules other-macro)) (same-macro? macro other-macro))
        ((Pair (ReservedAccessor) (ReservedAccessor)) #t)
        (_ #f)))

    (: same-macro? (impl (Fn Macro Macro -> Bool)))
    (define (same-macro? macro other)
      (and (same-library? (::library (::id macro)) (::library (::id other)))
           (= (::number (::id macro)) (::number (::id other)))))

    ;; Two resolutions are the same binding when both are bound to the
    ;; same thing; an unbound identifier is the same as nothing. Every type
    ;; variable and alias parameter is one, as the old expander gives them
    ;; all one identity.
    (: same-resolution? (impl (Fn Resolution Resolution -> Bool)))
    (define (same-resolution? resolution other)
      (match (Pair resolution other)
        ((Pair (BoundLocally denotation _) (BoundLocally other-denotation _))
         (same-denotation? denotation other-denotation))
        ((Pair (BoundAtTop meaning) (BoundAtTop other-meaning))
         (same-meaning? meaning other-meaning))
        (_ #f)))

    (: same-denotation? (impl (Fn Denotation Denotation -> Bool)))
    (define (same-denotation? denotation other)
      (match (Pair denotation other)
        ((Pair (LocalValue local) (LocalValue other-local))
         (= (::number local) (::number other-local)))
        ((Pair (LocalMacro macro) (LocalMacro other-macro)) (same-macro? macro other-macro))
        (_ (and (stands-for-type? denotation) (stands-for-type? other)))))

    (: stands-for-type? (impl (Fn Denotation -> Bool)))
    (define (stands-for-type? denotation)
      (match denotation
        ((TypeVariable _) #t)
        ((TypeArgument _) #t)
        (_ #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-scopes)
    (import
     (snail core table)
     (snail stage0 testing))
    (begin
      (define (test-scopes)
        (test-frames)
        (test-top-levels)
        (test-marks)
        (test-local-scopes)
        (test-macros)
        (test-identity)
        (test-written))

      ;; ---- Helpers ----

      (define a (list "a"))
      (define b (list "b"))
      (define c (list "c"))
      (define main (list "main"))

      (define (plain name)
        (Identifier name (Nil)))

      (define (value library name)
        (Value (TopGlobal (Global library name 0))))

      ;; A table of bindings, each a Pair of an identifier and a meaning,
      ;; in order.
      (define (bindings pairs)
        (fold-left (lambda (table pair)
                     (let ((name (::name (::first pair))))
                       (table-set table
                                  name
                                  (append (match (table-ref table name)
                                            ((Some found) found)
                                            ((None) (list)))
                                          (list (Binding (::first pair) (::second pair)))))))
                   empty-table
                   pairs))

      (define (top definitions imports)
        (TopScope (bindings definitions) (bindings imports)))

      (define (offered library definitions imports)
        (Offered library (Offer (list) (top definitions imports))))

      (define (scopes-of library here offers)
        (Scopes library here offers))

      (define (at library)
        (Env (list) library))

      (define (mark library number scope)
        (Mark library number scope))

      ;; ---- Cases ----

      ;; The innermost frame binding an identifier decides, before the top
      ;; level, and its home is the frames from it outward; a frame binds
      ;; only its own identifier, marks and all.
      (define (test-frames)
        (let* ((x (Local "x" 1))
               (y (Local "x" 2))
               (marked (Identifier "x" (list (mark main 3 (TopLevel main)))))
               (scopes
                (scopes-of main (top (list (Pair (plain "x") (value main "x"))) (list)) (list)))
               (outer (list (Frame (plain "x") (LocalValue x))))
               (frames (Cons (Frame (plain "z") (TypeVariable "z"))
                             (Cons (Frame (plain "x") (LocalValue y)) outer))))
          (expect (resolve scopes (Env frames main) (plain "x"))
                  (BoundLocally (LocalValue y) (list-tail frames 1)))
          (expect (resolve scopes (Env frames main) (plain "z"))
                  (BoundLocally (TypeVariable "z") frames))
          (expect (resolve scopes (Env (list (Frame marked (LocalValue x))) main) (plain "x"))
                  (BoundAtTop (value main "x")))
          (expect (resolve scopes (Env (list (Frame marked (LocalValue x))) main) marked)
                  (BoundLocally (LocalValue x) (list (Frame marked (LocalValue x)))))
          (expect (resolve scopes (at main) (plain "y")) (Unbound))))

      ;; A definition hides an import of its name; the top level is the
      ;; library's own while it expands, and else that library's offer.
      (define (test-top-levels)
        (let* ((here (top (list (Pair (plain "x") (value main "x")))
                          (list (Pair (plain "x") (value b "x")) (Pair (plain "y") (value b "y")))))
               (scopes (scopes-of main
                                  here
                                  (list
                                   (offered a (list (Pair (plain "x") (value a "x"))) (list))))))
          (expect (resolve scopes (at main) (plain "x")) (BoundAtTop (value main "x")))
          (expect (resolve scopes (at main) (plain "y")) (BoundAtTop (value b "y")))
          (expect (resolve scopes (at a) (plain "x")) (BoundAtTop (value a "x")))
          (expect (resolve scopes (at a) (plain "y")) (Unbound))))

      ;; An identifier a template introduced resolves without its latest
      ;; mark in that mark's scope when nothing binds it: here, (b)'s macro
      ;; wrote `helper`, which (b) imports from (c), and (main) used it.
      ;; One defined with the mark is found by it first.
      (define (test-marks)
        (let* ((from-b (mark main 7 (TopLevel b)))
               (from-c (mark main 8 (TopLevel c)))
               (helper (Identifier "helper" (list from-b)))
               (twice (Identifier "helper" (list from-c from-b)))
               (offers (list (offered b (list) (list (Pair (plain "helper") (value c "helper"))))
                             (offered c (list (Pair (plain "helper") (value c "helper"))) (list))))
               (here (top (list (Pair (plain "helper") (value main "helper"))) (list))))
          (expect (resolve (scopes-of main here offers) (at main) helper)
                  (BoundAtTop (value c "helper")))
          (expect (resolve (scopes-of main here offers) (at main) twice)
                  (BoundAtTop (value c "helper")))
          (expect (resolve (scopes-of main (top (list) (list)) offers)
                           (at main)
                           (Identifier "missing" (list from-b)))
                  (Unbound))
          (expect (resolve (scopes-of main
                                      (top (list (Pair helper
                                                       (Value (TopGlobal (Global main "helper" 1))))
                                                 (Pair (plain "helper") (value main "helper")))
                                           (list))
                                      offers)
                           (at main)
                           helper)
                  (BoundAtTop (Value (TopGlobal (Global main "helper" 1)))))))

      ;; A local mark's scope is the frames it holds, over the library's
      ;; top level, and none of the frames around the use.
      (define (test-local-scopes)
        (let* ((x (Local "x" 1))
               (shadow (Local "x" 2))
               (defined (list (Frame (plain "x") (LocalValue x))))
               (scopes (Scopes main (top (list (Pair (plain "y") (value main "y"))) (list)) (list)))
               (use (Env (list (Frame (plain "x") (LocalValue shadow))
                               (Frame (plain "y") (LocalValue shadow)))
                         main))
               (local-mark (mark main 6 (LocalScope defined))))
          (expect (scope-env scopes (LocalScope defined)) (Env defined main))
          (expect (scope-env scopes (TopLevel a)) (at a))
          (expect (resolve scopes use (Identifier "x" (list local-mark)))
                  (BoundLocally (LocalValue x) defined))
          (expect (resolve scopes use (Identifier "y" (list local-mark)))
                  (BoundAtTop (value main "y")))
          (expect (resolve scopes use (plain "x"))
                  (BoundLocally (LocalValue shadow) (::frames use)))))

      ;; A top-level macro's home is its library's top level; a local
      ;; macro's is its own frame outward, with itself in it. A head is a
      ;; form's first identifier.
      (define (test-macros)
        (let* ((top-macro (Macro (MacroId a 1) (list) (list)))
               (local-macro (Macro (MacroId main 2) (list) (list)))
               (outer (list (Frame (plain "x") (LocalValue (Local "x" 1)))))
               (home (Cons (Frame (plain "m") (LocalMacro local-macro)) outer))
               (frames (Cons (Frame (plain "y") (LocalValue (Local "y" 3))) home))
               (scopes (scopes-of main
                                  (top (list (Pair (plain "t") (MacroRules top-macro))) (list))
                                  (list)))
               (loc (Loc "t" 1 1)))
          (expect (resolved-macro (resolve scopes (Env frames main) (plain "t")))
                  (Some (MacroAt top-macro (TopLevel a))))
          (expect (resolved-macro (resolve scopes (Env frames main) (plain "m")))
                  (Some (MacroAt local-macro (LocalScope home))))
          (expect (resolved-macro (resolve scopes (Env frames main) (plain "y"))) (None))
          (expect (resolved-macro (Unbound)) (None))
          (expect (head-resolution scopes
                                   (Env frames main)
                                   (Form (list (Ident (plain "m") loc) (Ident (plain "y") loc))
                                         loc))
                  (BoundLocally (LocalMacro local-macro) home))
          (expect (head-resolution scopes (Env frames main) (Form (list) loc)) (Unbound))
          (expect (head-resolution scopes (Env frames main) (Ident (plain "m") loc)) (Unbound))))

      ;; Identity is by declaration, never by the name an import gives.
      (define (test-identity)
        (let ((point (Global a "Point" 0))
              (macro (Macro (MacroId a 3) (list) (list))))
          (expect (same-identifier? (plain "x") (plain "x")) #t)
          (expect (same-identifier? (plain "x") (plain "y")) #f)
          (expect (same-identifier? (Identifier "x" (list (mark a 1 (TopLevel a)))) (plain "x")) #f)
          (expect (same-identifier? (Identifier "x" (list (mark a 1 (TopLevel a))))
                                    (Identifier "x" (list (mark a 1 (TopLevel b)))))
                  #t)
          (expect (same-identifier? (Identifier "x" (list (mark a 1 (TopLevel a))))
                                    (Identifier "x" (list (mark b 1 (TopLevel a)))))
                  #f)
          (expect (same-meaning? (value a "x") (value a "x")) #t)
          (expect (same-meaning? (value a "x") (value b "x")) #f)
          (expect (same-meaning? (Value (TopGlobal (Global a "x" 1))) (value a "x")) #f)
          (expect (same-meaning? (Value (FieldFunction point "x" (Accessor)))
                                 (Value (FieldFunction point "x" (Accessor))))
                  #t)
          (expect (same-meaning? (Value (FieldFunction point "x" (Accessor)))
                                 (Value (FieldFunction point "x" (Replacer))))
                  #f)
          (expect (same-meaning? (TypeName point #t) (TypeName point #t)) #t)
          (expect (same-meaning? (TypeName point #t) (Value (TopGlobal point))) #f)
          (expect (same-meaning? (Keyword "if") (Keyword "if")) #t)
          (expect (same-meaning? (Keyword "if") (Keyword "let")) #f)
          (expect (same-meaning? (MacroRules macro)
                                 (MacroRules (Macro (MacroId a 3)
                                                    (list (Atom (syntax-Integer 1) (Loc "t" 1 1)))
                                                    (list))))
                  #t)
          (expect (same-meaning? (MacroRules macro)
                                 (MacroRules (Macro (MacroId b 3) (list) (list))))
                  #f)
          (expect (same-meaning? (ReservedAccessor) (ReservedAccessor)) #t)
          (expect (same-meaning? (Associated point "Output") (Associated point "Output")) #t)
          (expect (same-meaning? (Associated point "Output") (Associated point "Item")) #f)
          (expect (same-resolution? (BoundLocally (LocalValue (Local "x" 1)) (list))
                                    (BoundLocally (LocalValue (Local "y" 1)) (list)))
                  #t)
          (expect (same-resolution? (BoundLocally (LocalValue (Local "x" 1)) (list))
                                    (BoundLocally (LocalValue (Local "x" 2)) (list)))
                  #f)
          (expect (same-resolution? (BoundLocally (TypeVariable "a") (list))
                                    (BoundLocally (TypeArgument (Variable "b" (Loc "t" 1 1)))
                                                  (list)))
                  #t)
          (expect (same-resolution? (BoundLocally (TypeVariable "a") (list))
                                    (BoundLocally (LocalValue (Local "a" 1)) (list)))
                  #f)
          (expect (same-resolution? (Unbound) (Unbound)) #f)
          (expect (same-resolution? (BoundAtTop (Keyword "if")) (BoundAtTop (Keyword "if"))) #t)))

      ;; Written syntax carries no mark.
      (define (test-written)
        (let ((loc (Loc "t" 1 1)))
          (expect
           (written (syntax-Form (list (syntax-Ident "f" loc) (syntax-Atom (syntax-Integer 1) loc))
                                 loc))
           (Form (list (Ident (plain "f") loc) (Atom (syntax-Integer 1) loc)) loc))))))
   (else)))
