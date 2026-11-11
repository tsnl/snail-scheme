;; Macros: a `define-syntax` form becomes a macro's parts, and a use of a
;; macro becomes the syntax its first matching rule's template writes.
;; Rules are tried in order and each is read only when it is tried, so a
;; malformed rule after the one that matches is never reported, as the old
;; expander never reported it.
;;
;; Transcription is where hygiene starts. A template's pattern variable
;; becomes what it matched, untouched; every other identifier the template
;; writes gets the use's mark, the one mark of this expansion, which names
;; the scope the macro was defined in. So two uses' identifiers differ
;; however they are spelled, and (snail compiler expand scopes) resolves
;; each identifier the template introduced where the macro was defined.
;; A form the template writes is at the use, as an introduced identifier
;; is; an atom stays where the template writes it.
(define-library (snail compiler expand macros)
  (export
   macro-definition
   macro-use)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler expand marked)
   (snail compiler expand scopes)
   (snail compiler expand syntax-rules))
  (begin

    ;; ---- Definitions ----

    ;; The parts of a `define-syntax` form; whoever binds the macro gives
    ;; it its id and scope.
    (: macro-definition (impl (Fn Marked -> (Result MacroForm (List Feedback)))))
    (define (macro-definition form)
      (match (macro-shape form)
        ((WellFormedMacro parts) (Ok parts))
        ((MalformedMacro loc message) (fail loc message))))

    ;; ---- Uses ----

    ;; The syntax the macro `found` writes for a use at `loc` whose items
    ;; after its head are `arguments`, in the environment `env` of the use.
    ;; `number` is the use's own, fresh in the library being expanded, and
    ;; makes its mark, which names the macro's home.
    (: macro-use
       (impl (Fn Scopes Env MacroAt (List Marked) Loc I64 -> (Result Marked (List Feedback)))))
    (define (macro-use scopes env found arguments loc number)
      (first-match
       (Matcher (::literals (::macro found)) scopes env (scope-env scopes (::home found)))
       (::rules (::macro found))
       arguments
       (Transcribing (Mark (::library scopes) number (::home found)) loc)))

    ;; One use being transcribed: its mark, and where it is.
    (struct Transcribing
      ((mark Mark)
       (loc Loc)))

    (: first-match
       (impl
        (Fn Matcher (List Marked) (List Marked) Transcribing -> (Result Marked (List Feedback)))))
    (define (first-match matcher rules arguments use)
      (match rules
        ((Nil) (fail (::loc use) "no syntax-rules pattern matches this use"))
        ((Cons rule more)
         (match (rule-form rule)
           ((Err message) (fail (marked-loc rule) message))
           ((Ok form)
            (match (match-rule matcher (::patterns form) arguments)
              ((Matched captures) (transcribe (::template form) captures use))
              ((Mismatched) (first-match matcher more arguments use))
              ;; A deviation, approved: where matching meets a literal that
              ;; is not an identifier, the old expander stopped with an
              ;; internal error; this reports the literal.
              ((MalformedLiteral loc message) (fail loc message))))))))

    ;; ---- Transcription ----

    (: transcribe
       (impl (Fn Marked (List Capture) Transcribing -> (Result Marked (List Feedback)))))
    (define (transcribe template captures use)
      (match template
        ((Ident identifier _)
         (match (bound-to captures identifier)
           ((None) (Ok (Ident (marked identifier (::mark use)) (::loc use))))
           ((Some (One syntax)) (Ok syntax))
           ((Some (Many _))
            (fail (::loc use)
                  (string-append "pattern variable used without an ellipsis: "
                                 (::name identifier))))))
        ((Atom _ _) (Ok template))
        ((Form items _)
         (result-let* ((transcribed (transcribe-items items captures use)))
           (Ok (Form transcribed (::loc use)))))))

    ;; A form's items, each item followed by `...` repeated once for each
    ;; of its variables' matches.
    (: transcribe-items
       (impl
        (Fn (List Marked) (List Capture) Transcribing -> (Result (List Marked) (List Feedback)))))
    (define (transcribe-items items captures use)
      (match items
        ((Nil) (Ok (Nil)))
        ((Cons item (Cons (Ident (Identifier "..." _) _) rest))
         (result-let* ((repeated (transcribe-repeated item captures use))
                       (after (transcribe-items rest captures use)))
           (Ok (append repeated after))))
        ((Cons item rest)
         (result-let* ((first (transcribe item captures use))
                       (after (transcribe-items rest captures use)))
           (Ok (Cons first after))))))

    ;; A repeated template, once for each match of the variables in it that
    ;; matched under an ellipsis, which must have matched alike many times;
    ;; each time, every such variable is bound to its next match.
    (: transcribe-repeated
       (impl (Fn Marked (List Capture) Transcribing -> (Result (List Marked) (List Feedback)))))
    (define (transcribe-repeated template captures use)
      (match (repeated-captures template captures)
        ((Nil) (fail (::loc use) "ellipsis follows a template without pattern variables"))
        ((Cons first rest)
         (let ((count (length (::matches first))))
           (if (every? (lambda (repeated) (= (length (::matches repeated)) count)) rest)
               (map-results (lambda (index)
                              (transcribe template
                                          (append
                                           (map (lambda (repeated) (repetition repeated index))
                                                (Cons first rest))
                                           captures)
                                          use))
                            (iota count))
               (fail (::loc use)
                     "pattern variables under one ellipsis matched different lengths"))))))

    ;; A variable a template repeats, and its matches, one for each time.
    (struct Repeated
      ((variable Identifier)
       (matches (List Bound))))

    (: repetition (impl (Fn Repeated I64 -> Capture)))
    (define (repetition repeated index)
      (Capture (::variable repeated) (list-ref (::matches repeated) index)))

    ;; Each identifier of `template`, once, that `captures` binds under an
    ;; ellipsis, in the order the template writes them.
    (: repeated-captures (impl (Fn Marked (List Capture) -> (List Repeated))))
    (define (repeated-captures template captures)
      (concatenate (map (lambda (identifier)
                          (match (bound-to captures identifier)
                            ((Some (Many matches)) (list (Repeated identifier matches)))
                            (_ (Nil))))
                        (distinct (template-identifiers template)))))

    (: template-identifiers (impl (Fn Marked -> (List Identifier))))
    (define (template-identifiers template)
      (match template
        ((Ident identifier _) (list identifier))
        ((Form items _) (concatenate (map template-identifiers items)))
        ((Atom _ _) (Nil))))

    (: distinct (impl (Fn (List Identifier) -> (List Identifier))))
    (define (distinct identifiers)
      (reverse (fold-left (lambda (kept identifier)
                            (if (any? (lambda (other) (same-identifier? other identifier)) kept)
                                kept
                                (Cons identifier kept)))
                          (Nil)
                          identifiers)))

    ;; What the innermost capture of `identifier` bound it to.
    (: bound-to (impl (Fn (List Capture) Identifier -> (Option Bound))))
    (define (bound-to captures identifier)
      (match (find (lambda (capture) (same-identifier? (::variable capture) identifier)) captures)
        ((Some capture) (Some (::bound capture)))
        ((None) (None))))

    ;; `identifier` as this expansion introduces it.
    (: marked (impl (Fn Identifier Mark -> Identifier)))
    (define (marked identifier mark)
      (Identifier (::name identifier) (Cons mark (::marks identifier))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-macros)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail core table)
     (prefix (snail compiler read language) syntax-)
     (snail compiler expand language)
     (snail compiler expand offer)
     (snail stage0 testing))
    (begin
      (define (test-macros)
        (test-definitions)
        (test-rules)
        (test-transcription)
        (test-ellipses)
        (test-hygiene)
        (test-bad-literal))

      ;; ---- Helpers ----

      (define use-loc (Loc "main.sld" 9 1))

      (define (at line)
        (Loc "lib.sld" line 1))

      (define main (list "main"))
      (define lib (list "lib"))
      (define other (list "other"))

      ;; Marked syntax for quoted data at `loc`, with no marks.
      (define (marked-at loc datum)
        (cond ((or (null? datum) (pair? datum))
               (Form (map (lambda (item) (marked-at loc item)) datum) loc))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) loc))
              ((string? datum) (Atom (syntax-Text datum) loc))
              ((exact-integer? datum) (Atom (syntax-Integer datum) loc))
              ((boolean? datum) (Atom (syntax-Boolean datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (plain name)
        (Identifier name (Nil)))

      (define (value library name)
        (Value (TopGlobal (Global library name 0))))

      (define (scope-of pairs)
        (fold-left (lambda (table pair)
                     (table-set table
                                (::name (::first pair))
                                (list (Binding (::first pair) (::second pair)))))
                   empty-table
                   pairs))

      ;; (lib) defines `helper` and imports `list` from (other), whose
      ;; top level defines it; (main), expanding, defines its own `helper`.
      (define offers
        (list (Offered lib
                       (Offer (list)
                              (TopScope
                               (scope-of (list (Pair (plain "helper") (value lib "helper"))))
                               (scope-of (list (Pair (plain "list") (value other "list")))))))
              (Offered other
                       (Offer (list)
                              (TopScope (scope-of (list (Pair (plain "list") (value other "list"))))
                                        empty-table)))))

      (define scopes
        (Scopes main
                (TopScope (scope-of (list (Pair (plain "helper") (value main "helper"))))
                          empty-table)
                offers))

      (define top
        (Env (list) main))

      ;; A macro of (lib), its rules written at line `line` and after.
      (define (lib-macro literals rules)
        (Macro (MacroId lib 1)
               (map (lambda (literal) (marked-at (at 1) literal)) literals)
               (map (lambda (rule) (marked-at (at 2) rule)) rules)))

      ;; The use (m argument ...) in (main), with mark number 4.
      (define (use macro arguments)
        (macro-use scopes
                   top
                   (MacroAt macro (TopLevel lib))
                   (map (lambda (argument) (marked-at use-loc argument)) arguments)
                   use-loc
                   4))

      (define lib-mark
        (Mark main 4 (TopLevel lib)))

      (define (introduced name)
        (Ident (Identifier name (list lib-mark)) use-loc))

      ;; ---- Cases ----

      (define (test-definitions)
        (expect (macro-definition (marked-at use-loc '(define-syntax m (syntax-rules () ((_) 1)))))
                (Ok (MacroForm (plain "m") use-loc (list) (list (marked-at use-loc '((_) 1))))))
        (expect (macro-definition (marked-at use-loc '(define-syntax m)))
                (fail use-loc
                      "expected (define-syntax name (syntax-rules (literal ...) rule ...))"))
        (expect (macro-definition (Form (list (marked-at use-loc 'define-syntax)
                                              (marked-at (at 3) "m")
                                              (marked-at use-loc '(syntax-rules ())))
                                        use-loc))
                (fail (at 3) "expected a macro name")))

      ;; The first rule that matches writes the use's syntax; a malformed
      ;; rule is reported when it is tried, and only then.
      (define (test-rules)
        (expect (use (lib-macro '() '(((_ a) 1) ((_ a b) 2) bogus)) '(x y))
                (Ok (Atom (syntax-Integer 2) (at 2))))
        (expect (use (lib-macro '() '(((_) 1))) '(x))
                (fail use-loc "no syntax-rules pattern matches this use"))
        (expect (use (lib-macro '() '()) '())
                (fail use-loc "no syntax-rules pattern matches this use"))
        (expect (use (lib-macro '() '(((_ a) 1) (bogus))) '(x y))
                (fail (at 2) "expected ((_ pattern ...) template)")))

      ;; A pattern variable is what it matched; any other identifier is
      ;; marked, and a form is at the use, while an atom keeps its place.
      (define (test-transcription)
        (expect (use (lib-macro '() '(((_ a) (helper a 3)))) '((f x)))
                (Ok (Form (list (introduced "helper")
                                (marked-at use-loc '(f x))
                                (Atom (syntax-Integer 3) (at 2)))
                          use-loc)))
        (expect (use (lib-macro '() '(((_ a ...) a))) '(1))
                (fail use-loc "pattern variable used without an ellipsis: a")))

      (define (test-ellipses)
        (expect (use (lib-macro '() '(((_ (k v) ...) (list (k v) ... done)))) '((1 2) (3 4)))
                (Ok (Form (list (introduced "list")
                                (Form (list (marked-at use-loc 1) (marked-at use-loc 2)) use-loc)
                                (Form (list (marked-at use-loc 3) (marked-at use-loc 4)) use-loc)
                                (introduced "done"))
                          use-loc)))
        (expect (use (lib-macro '() '(((_ (a ...) ...) (f (a ...) ...)))) '((1 2) (3)))
                (Ok (Form (list (introduced "f")
                                (Form (list (marked-at use-loc 1) (marked-at use-loc 2)) use-loc)
                                (Form (list (marked-at use-loc 3)) use-loc))
                          use-loc)))
        (expect (use (lib-macro '() '(((_ (a ...) ...) (f a ... ...)))) '((1 2) (3)))
                (fail use-loc "pattern variable used without an ellipsis: a"))
        (expect (use (lib-macro '() '(((_ a ...) (x ...)))) '(1))
                (fail use-loc "ellipsis follows a template without pattern variables"))
        (expect (use (lib-macro '() '(((_ (a ...) (b ...)) ((a b) ...)))) '((1 2) (3)))
                (fail use-loc "pattern variables under one ellipsis matched different lengths"))
        (expect (use (lib-macro '() '(((_ a ...) (a ...)))) '())
                (Ok (Form (list) use-loc))))

      ;; The template's `helper` means (lib)'s, though (main) defines one,
      ;; and its `list` the (other) library's, which (lib) imports; the
      ;; use's own `helper` stays (main)'s.
      (define (test-hygiene)
        (match (use (lib-macro '() '(((_ a) (helper a list)))) '(helper))
          ((Ok (Form (Cons (Ident from-template _)
                           (Cons (Ident from-use _) (Cons (Ident listed _) (Nil))))
                     _))
           (expect (resolve scopes top from-template) (BoundAtTop (value lib "helper")))
           (expect (resolve scopes top from-use) (BoundAtTop (value main "helper")))
           (expect (resolve scopes top listed) (BoundAtTop (value other "list"))))
          (unexpected (expect unexpected "a form of three identifiers"))))

      ;; Approved deviation: a literal that is not an identifier is
      ;; reported where it is written, when matching meets it.
      (define (test-bad-literal)
        (let ((macro (Macro (MacroId lib 1)
                            (list (Atom (syntax-Integer 5) (at 7)))
                            (list (marked-at (at 2) '((_ a) a))))))
          (expect (macro-use scopes
                             top
                             (MacroAt macro (TopLevel lib))
                             (list (marked-at use-loc 'x))
                             use-loc
                             4)
                  (fail (at 7) "expected an identifier"))))))
   (else)))
