;; Patterns: a match clause's pattern becomes a Pattern and the frames
;; that bind its variables, which its body sees. Its variables must be
;; distinct; then each is bound to a fresh local where it is met, in the
;; order written, and each constructor is resolved where the match is
;; written. A variable is any identifier but `_` that is not at the head
;; of a form, and the head of a form is its constructor, which is always
;; applied, as in `(None)`.
(define-library (snail compiler expand patterns)
  (export
   Patterned
   expand-pattern
   constructor-of)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler read language) syntax-)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand scopes)
   (snail compiler expand state))
  (begin

    ;; ---- Variables ----

    ;; A variable where it is written.
    (struct Occurrence
      ((identifier Identifier)
       (loc Loc)))

    ;; The variables of a pattern, in the order written, each once. The
    ;; first variable written twice is reported where it is first written.
    (: pattern-variables (impl (Fn Marked -> (Result (List Identifier) (List Feedback)))))
    (define (pattern-variables syntax)
      (let ((variables (variable-occurrences syntax)))
        (match (find (lambda (variable) (written-twice? variable variables)) variables)
          ((Some twice)
           (fail (::loc twice)
                 (string-append "pattern variable bound twice: " (::name (::identifier twice)))))
          ((None) (Ok (map ::identifier variables))))))

    (: variable-occurrences (impl (Fn Marked -> (List Occurrence))))
    (define (variable-occurrences syntax)
      (match syntax
        ((Ident (Identifier "_" _) _) (Nil))
        ((Ident identifier loc) (list (Occurrence identifier loc)))
        ((Form (Cons _ arguments) _) (concatenate (map variable-occurrences arguments)))
        (_ (Nil))))

    (: written-twice? (impl (Fn Occurrence (List Occurrence) -> Bool)))
    (define (written-twice? variable variables)
      (< 1
         (length (filter (lambda (other)
                           (same-identifier? (::identifier other) (::identifier variable)))
                         variables))))

    ;; ---- Patterns ----

    ;; A pattern, and a frame for each of its variables, in the order
    ;; written.
    (struct Patterned
      ((pattern Pattern)
       (frames (List Frame))))

    ;; The pattern `syntax`, as a match written in `env` sees it, once its
    ;; variables are found to be distinct.
    (: expand-pattern
       (impl
        (Fn Expanding Scopes Env Marked -> (Result (Pair Patterned Expanding) (List Feedback)))))
    (define (expand-pattern state scopes env syntax)
      (expanding-let* ((variables state (unchanged state (pattern-variables syntax))))
        (pattern-of state scopes env syntax)))

    ;; A constructor is resolved before the patterns it is applied to.
    (: pattern-of
       (impl
        (Fn Expanding Scopes Env Marked -> (Result (Pair Patterned Expanding) (List Feedback)))))
    (define (pattern-of state scopes env syntax)
      (match syntax
        ((Ident (Identifier "_" _) loc) (Ok (Pair (Patterned (Wild loc) (Nil)) state)))
        ((Ident identifier loc)
         (expanding-let* ((number state (fresh state)))
           (let ((local (Local (::name identifier) number)))
             (Ok (Pair (Patterned (Bind local loc) (list (Frame identifier (LocalValue local))))
                       state)))))
        ((Atom (syntax-ByteVector _) loc) (fail loc "a byte vector cannot be a pattern"))
        ((Atom datum loc) (Ok (Pair (Patterned (Equals datum loc) (Nil)) state)))
        ((Form (Cons head arguments) _)
         (expanding-let* ((constructor state (unchanged state (constructor-of scopes env head)))
                          (parts state (expanding-map state
                                                      (lambda (state argument)
                                                        (pattern-of state scopes env argument))
                                                      arguments)))
           (Ok (Pair (Patterned (Destructure constructor (map ::pattern parts) (marked-loc head))
                                (concatenate (map ::frames parts)))
                     state))))
        ((Form (Nil) loc) (fail loc "expected a pattern"))))

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

      ;; Variables are bound in the order written, numbered from the
      ;; state.
      (define (test-expansion)
        (define (expanded syntax)
          (match (expand-pattern (Expanding 2) scopes env syntax)
            ((Ok (Pair patterned _)) (Ok patterned))
            ((Err feedback) (Err feedback))))
        (define (frame name number)
          (Frame (plain name) (LocalValue (Local name number))))
        (expect (expanded (marked '_)) (Ok (Patterned (Wild loc) (list))))
        (expect (expanded (marked 'a))
                (Ok (Patterned (Bind (Local "a" 2) loc) (list (frame "a" 2)))))
        (expect (expanded (marked 5)) (Ok (Patterned (Equals (syntax-Integer 5) loc) (list))))
        (expect (expanded (Atom (syntax-ByteVector (list->vector (list 1))) (at 2)))
                (fail (at 2) "a byte vector cannot be a pattern"))
        (expect (expanded (marked '(Some (Point a _) b)))
                (Ok (Patterned (Destructure (TopGlobal (global "Some"))
                                            (list (Destructure (TopGlobal (global "Point"))
                                                               (list (Bind (Local "a" 2) loc)
                                                                     (Wild loc))
                                                               loc)
                                                  (Bind (Local "b" 3) loc))
                                            loc)
                               (list (frame "a" 2) (frame "b" 3)))))
        (expect (expanded (marked '(Some)))
                (Ok (Patterned (Destructure (TopGlobal (global "Some")) (list) loc) (list))))
        (expect (expanded (marked '())) (fail loc "expected a pattern"))
        (expect (expanded (Form (list (marked 'Missing)
                                      (Atom (syntax-ByteVector (list->vector (list 1))) (at 2)))
                                loc))
                (fail loc "not a constructor: Missing"))
        (expect
         (expanded (Form (list (marked 'Missing) (marked 'a) (Ident (plain "a") (at 2))) loc))
         (fail loc "pattern variable bound twice: a")))

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
