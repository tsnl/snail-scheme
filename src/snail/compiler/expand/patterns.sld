;; Patterns: a match clause's pattern becomes a Pattern. A clause binds
;; its pattern's variables before the pattern is expanded, so the pattern
;; only looks names up: each variable in the frames the clause made, and
;; each constructor where the match is written. A variable is any
;; identifier but `_` that is not at the head of a form, and the head of a
;; form is its constructor, which is always applied, as in `(None)`.
(define-library (snail compiler expand patterns)
  (export
   pattern-variables
   expand-pattern
   constructor-of)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand scopes))
  (begin

    ;; ---- Variables ----

    ;; The variables of a pattern, in the order written, each once. The
    ;; first variable written twice is reported where it is first written.
    (: pattern-variables (impl (Fn Marked -> (Result (List Identifier) (List Feedback)))))
    (define (pattern-variables syntax)
      (let ((variables (variable-occurrences syntax)))
        (match (find (lambda (variable) (written-twice? variable variables)) variables)
          ((Some (Ident identifier loc))
           (fail loc (string-append "pattern variable bound twice: " (::name identifier))))
          (_ (Ok (map occurrence-identifier variables))))))

    ;; Each variable's identifier where it is written.
    (: variable-occurrences (impl (Fn Marked -> (List Marked))))
    (define (variable-occurrences syntax)
      (match syntax
        ((Ident (Identifier "_" _) _) (Nil))
        ((Ident _ _) (list syntax))
        ((Form (Cons _ arguments) _) (concatenate (map variable-occurrences arguments)))
        (_ (Nil))))

    (: written-twice? (impl (Fn Marked (List Marked) -> Bool)))
    (define (written-twice? variable variables)
      (< 1
         (length (filter (lambda (other)
                           (same-identifier? (occurrence-identifier other)
                                             (occurrence-identifier variable)))
                         variables))))

    ;; Only an identifier is a variable's occurrence.
    (: occurrence-identifier (impl (Fn Marked -> Identifier)))
    (define (occurrence-identifier syntax)
      (match syntax
        ((Ident identifier _) identifier)
        (_ (panic "internal error: only an identifier is a variable's occurrence"))))

    ;; ---- Patterns ----

    ;; The pattern `syntax`, whose variables `bound` has bound, as a match
    ;; written in `env` sees it. A constructor is resolved before the
    ;; patterns it is applied to.
    (: expand-pattern (impl (Fn Scopes Env Env Marked -> (Result Pattern (List Feedback)))))
    (define (expand-pattern scopes env bound syntax)
      (match syntax
        ((Ident (Identifier "_" _) loc) (Ok (Wild loc)))
        ((Ident identifier loc) (Ok (Bind (bound-variable scopes bound identifier) loc)))
        ((Atom (syntax-ByteVector _) loc) (fail loc "a byte vector cannot be a pattern"))
        ((Atom datum loc) (Ok (Equals datum loc)))
        ((Form (Cons head arguments) _)
         (result-let* ((constructor (constructor-of scopes env head))
                       (patterns (map-results (lambda (argument)
                                                (expand-pattern scopes env bound argument))
                                              arguments)))
           (Ok (Destructure constructor patterns (marked-loc head)))))
        ((Form (Nil) loc) (fail loc "expected a pattern"))))

    ;; A variable's local. `pattern-variables` gave every variable a frame
    ;; of `bound`, the innermost frames, so each resolves to its own.
    (: bound-variable (impl (Fn Scopes Env Identifier -> Local)))
    (define (bound-variable scopes bound identifier)
      (match (resolve scopes bound identifier)
        ((BoundLocally (LocalValue local) _) local)
        (_ (panic "internal error: a pattern variable is bound before its pattern is expanded"))))

    ;; ---- Constructors ----

    ;; What the head of a pattern or a `case-id` names: a value, or a
    ;; struct, whose name is its constructor. Whether a value is a
    ;; constructor is decided once declarations are, as is whether its type
    ;; may be taken apart here.
    (: constructor-of (impl (Fn Scopes Env Marked -> (Result TopValue (List Feedback)))))
    (define (constructor-of scopes env syntax)
      (match syntax
        ((Ident identifier loc)
         (match (resolve scopes env identifier)
           ((BoundAtTop (Value value)) (Ok value))
           ((BoundAtTop (TypeName global #t)) (Ok (TopGlobal global)))
           (_ (fail loc (string-append "not a constructor: " (::name identifier))))))
        (_ (fail (marked-loc syntax) "expected a constructor"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-patterns)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail core table)
     (snail stage0 testing))
    (begin
      (define (test-patterns)
        (test-variables)
        (test-expansion)
        (test-constructors))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))

      (define main (list "main"))

      (define (marked datum)
        (cond ((or (null? datum) (pair? datum)) (Form (map marked datum) loc))
              ((symbol? datum) (Ident (plain (symbol->string datum)) loc))
              ((string? datum) (Atom (syntax-Text datum) loc))
              ((exact-integer? datum) (Atom (syntax-Integer datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (plain name)
        (Identifier name (Nil)))

      (define (global name)
        (Global main name 0))

      (define (definitions pairs)
        (fold-left (lambda (table pair)
                     (table-set table
                                (::first pair)
                                (list (Binding (plain (::first pair)) (::second pair)))))
                   empty-table
                   pairs))

      ;; (main) defines Some, the struct Point, the enum Shape and `x`.
      (define scopes
        (Scopes main
                (TopScope (definitions (list (Pair "Some" (Value (TopGlobal (global "Some"))))
                                             (Pair "Point" (TypeName (global "Point") #t))
                                             (Pair "Shape" (TypeName (global "Shape") #f))
                                             (Pair "Ok"
                                                   (Value (FieldFunction (global "Ok")
                                                                         "value"
                                                                         (Accessor))))))
                          empty-table)
                (list)))

      (define env
        (Env (list (Frame (plain "y") (LocalValue (Local "y" 1)))) main))

      (define (bound-in names)
        (Env (fold-left (lambda (frames pair)
                          (Cons (Frame (plain (::first pair))
                                       (LocalValue (Local (::first pair) (::second pair))))
                                frames))
                        (::frames env)
                        names)
             main))

      ;; Heads and `_` are no variables; a variable written twice is
      ;; reported where it is first written.
      (define (test-variables)
        (expect (pattern-variables (marked '(Some (Pair a _) b)))
                (Ok (list (plain "a") (plain "b"))))
        (expect (pattern-variables (marked 'a)) (Ok (list (plain "a"))))
        (expect (pattern-variables (marked '_)) (Ok (list)))
        (expect (pattern-variables (marked '(Some 1 "s"))) (Ok (list)))
        (expect (pattern-variables (Form (list (marked 'Pair)
                                               (Ident (plain "a") (at 2))
                                               (Ident (plain "b") (at 3))
                                               (Ident (plain "a") (at 4)))
                                         loc))
                (fail (at 2) "pattern variable bound twice: a"))
        (expect (pattern-variables (Form (list (marked 'Pair)
                                               (Ident (plain "a") (at 2))
                                               (Ident (Identifier "a"
                                                                  (list
                                                                   (Mark main 1 (TopLevel main))))
                                                      (at 3)))
                                         loc))
                (Ok (list (plain "a") (Identifier "a" (list (Mark main 1 (TopLevel main))))))))

      (define (test-expansion)
        (let ((bound (bound-in (list (Pair "a" 2) (Pair "b" 3)))))
          (expect (expand-pattern scopes env bound (marked '_)) (Ok (Wild loc)))
          (expect (expand-pattern scopes env bound (marked 'a)) (Ok (Bind (Local "a" 2) loc)))
          (expect (expand-pattern scopes env bound (marked 5)) (Ok (Equals (syntax-Integer 5) loc)))
          (expect (expand-pattern scopes
                                  env
                                  bound
                                  (Atom (syntax-ByteVector (list->vector (list 1))) (at 2)))
                  (fail (at 2) "a byte vector cannot be a pattern"))
          (expect (expand-pattern scopes env bound (marked '(Some (Point a _) b)))
                  (Ok (Destructure (TopGlobal (global "Some"))
                                   (list (Destructure (TopGlobal (global "Point"))
                                                      (list (Bind (Local "a" 2) loc) (Wild loc))
                                                      loc)
                                         (Bind (Local "b" 3) loc))
                                   loc)))
          (expect (expand-pattern scopes env bound (marked '(Some)))
                  (Ok (Destructure (TopGlobal (global "Some")) (list) loc)))
          (expect (expand-pattern scopes env bound (marked '())) (fail loc "expected a pattern"))
          (expect (expand-pattern scopes
                                  env
                                  bound
                                  (Form (list (marked 'Missing)
                                              (Atom (syntax-ByteVector (list->vector (list 1)))
                                                    (at 2)))
                                        loc))
                  (fail loc "not a constructor: Missing"))))

      ;; A head is a value or a struct, resolved where the match is.
      (define (test-constructors)
        (expect (constructor-of scopes env (marked 'Point)) (Ok (TopGlobal (global "Point"))))
        (expect (constructor-of scopes env (marked 'Ok))
                (Ok (FieldFunction (global "Ok") "value" (Accessor))))
        (expect (constructor-of scopes env (marked 'Shape)) (fail loc "not a constructor: Shape"))
        (expect (constructor-of scopes env (marked 'y)) (fail loc "not a constructor: y"))
        (expect (constructor-of scopes env (marked 'Missing))
                (fail loc "not a constructor: Missing"))
        (expect (constructor-of scopes env (Atom (syntax-Integer 1) (at 3)))
                (fail (at 3) "expected a constructor"))
        (expect (constructor-of scopes env (marked '(Some))) (fail loc "expected a constructor")))))
   (else)))
