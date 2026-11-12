;; What a `syntax-rules` macro decides from the syntax it is handed: the
;; shape of its definition, the shape of each of its rules, and whether a
;; rule's pattern matches a use, with what each pattern variable matched.
;; The part (snail compiler expand macros) acts on the answers.
;;
;; Matching walks a pattern beside the use, as the old expander does:
;; `_` matches anything, an identifier listed as a literal matches an
;; identifier with the same binding, any other identifier is a pattern
;; variable, an atom matches an equal atom, a form matches a form item by
;; item, and an item followed by `...` matches as many items as the items
;; after it leave. `_` and `...` are known by name, whatever their marks.
;; A literal that is not an identifier is no literal at all; the old
;; expander stopped with an internal error wherever it met one while
;; matching, and this rule answers there that it met one instead. A
;; malformed definition, rule or literal is answered with what to say of
;; it, and where, which the part places.
(define-library (snail compiler expand syntax-rules)
  (export
   MacroShape
   WellFormedMacro
   MalformedMacro
   MacroForm
   macro-shape
   RuleForm
   rule-form
   Bound
   One
   Many
   Capture
   Matcher
   Matching
   Matched
   Mismatched
   MalformedLiteral
   match-rule)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler literals datum) Datum)
   (prefix (snail compiler literals datum) datum-)
   (snail compiler expand marked)
   (snail compiler expand scopes))
  (begin

    ;; ---- Definitions ----

    ;; `(define-syntax name (syntax-rules (literal ...) rule ...))`, whose
    ;; head the caller has resolved. `syntax-rules` is known by name.
    (enum MacroShape
      (WellFormedMacro
       ((form MacroForm)))
      (MalformedMacro
       ((loc Loc)
        (message String))))

    (struct MacroForm
      ((name Identifier)
       (name-loc Loc)
       (literals (List Marked))
       (rules (List Marked))))

    (: macro-shape (impl (Fn Marked -> MacroShape)))
    (define (macro-shape form)
      (match form
        ((Form (Cons _
                     (Cons name
                           (Cons (Form (Cons (Ident (Identifier "syntax-rules" _) _)
                                             (Cons (Form literals _) rules))
                                       _)
                                 (Nil))))
               _)
         (match name
           ((Ident identifier loc) (WellFormedMacro (MacroForm identifier loc literals rules)))
           (_ (MalformedMacro (marked-loc name) "expected a macro name"))))
        (_
         (MalformedMacro (marked-loc form)
                         "expected (define-syntax name (syntax-rules (literal ...) rule ...))"))))

    ;; ---- Rules ----

    ;; `((_ pattern ...) template)`: a rule's patterns follow a head that
    ;; matches nothing, since the use's head is the macro.
    (struct RuleForm
      ((patterns (List Marked))
       (template Marked)))

    ;; A rule of another shape is refused at the rule.
    (: rule-form (impl (Fn Marked -> (Result RuleForm String))))
    (define (rule-form rule)
      (match rule
        ((Form (Cons (Form (Cons _ patterns) _) (Cons template (Nil))) _)
         (Ok (RuleForm patterns template)))
        (_ (Err "expected ((_ pattern ...) template)"))))

    ;; ---- Matching ----

    ;; What a pattern variable matched: one form, or, under n ellipses, a
    ;; depth-n nesting of what each repetition matched.
    (enum Bound
      (One
       ((syntax Marked)))
      (Many
       ((matches (List Bound)))))

    ;; A pattern variable and what it matched.
    (struct Capture
      ((variable Identifier)
       (bound Bound)))

    ;; What matching consults: the macro's literals, and the scopes to
    ;; resolve an identifier in where the use writes it, `use`, and where
    ;; the macro was defined, `definition`, to compare it with a literal.
    (struct Matcher
      ((literals (List Marked))
       (scopes Scopes)
       (use Env)
       (definition Env)))

    ;; A match, in the pattern's order, or why there is none.
    (enum Matching
      (Matched
       ((captures (List Capture))))
      (Mismatched)
      (MalformedLiteral
       ((loc Loc)
        (message String))))

    ;; Whether a rule's patterns match the items of a use after its head.
    (: match-rule (impl (Fn Matcher (List Marked) (List Marked) -> Matching)))
    (define (match-rule matcher patterns inputs)
      (match-items matcher patterns inputs))

    (: match-pattern (impl (Fn Matcher Marked Marked -> Matching)))
    (define (match-pattern matcher pattern input)
      (match pattern
        ((Ident identifier _)
         (if (string=? (::name identifier) "_")
             (Matched (Nil))
             (match (literal-check (::literals matcher) identifier)
               ((NotLiteral) (Matched (list (Capture identifier (One input)))))
               ((IsLiteral)
                (if (same-binding? matcher input identifier) (Matched (Nil)) (Mismatched)))
               ((BadLiteral literal) (malformed-literal literal)))))
        ((Atom datum _)
         (match input
           ((Atom other _) (if (same-datum? datum other) (Matched (Nil)) (Mismatched)))
           (_ (Mismatched))))
        ((Form items _)
         (match input
           ((Form inputs _) (match-items matcher items inputs))
           (_ (Mismatched))))))

    (: match-items (impl (Fn Matcher (List Marked) (List Marked) -> Matching)))
    (define (match-items matcher patterns inputs)
      (match patterns
        ((Cons repeated (Cons (Ident (Identifier "..." _) _) after))
         (match-repeated matcher repeated after inputs))
        ((Nil) (if (null? inputs) (Matched (Nil)) (Mismatched)))
        ((Cons pattern more)
         (match inputs
           ((Nil) (Mismatched))
           ((Cons input rest)
            (match (match-pattern matcher pattern input)
              ((Matched captures) (prepended captures (match-items matcher more rest)))
              (unmatched unmatched)))))))

    (: prepended (impl (Fn (List Capture) Matching -> Matching)))
    (define (prepended captures matching)
      (match matching
        ((Matched more) (Matched (append captures more)))
        (unmatched unmatched)))

    ;; `repeated ...` takes the items the patterns after it leave. The
    ;; patterns after it are matched first; then every repetition, as the
    ;; old expander matches them all before it looks at any.
    (: match-repeated (impl (Fn Matcher Marked (List Marked) (List Marked) -> Matching)))
    (define (match-repeated matcher repeated after inputs)
      (let ((count (- (length inputs) (length after))))
        (if (< count 0)
            (Mismatched)
            (match (match-items matcher after (list-drop inputs count))
              ((Matched tail)
               (repetitions matcher
                            repeated
                            (map (lambda (input) (match-pattern matcher repeated input))
                                 (take inputs count))
                            tail))
              (unmatched unmatched)))))

    ;; Each of the repeated pattern's variables, bound to what it matched
    ;; in each repetition, before what the patterns after it matched.
    (: repetitions (impl (Fn Matcher Marked (List Matching) (List Capture) -> Matching)))
    (define (repetitions matcher repeated matchings tail)
      (match (find literal-problem? matchings)
        ((Some problem) problem)
        ((None)
         (match (every-capture matchings)
           ((None) (Mismatched))
           ((Some repeats)
            (match (pattern-variables (::literals matcher) repeated)
              ((Ok variables)
               (Matched (append (map (lambda (variable) (repeated-capture variable repeats))
                                     variables)
                                tail)))
              ((Err literal) (malformed-literal literal))))))))

    ;; What each repetition captured, when every one matched.
    (: every-capture (impl (Fn (List Matching) -> (Option (List (List Capture))))))
    (define (every-capture matchings)
      (match matchings
        ((Nil) (Some (Nil)))
        ((Cons (Matched captures) rest)
         (match (every-capture rest)
           ((Some more) (Some (Cons captures more)))
           ((None) (None))))
        (_ (None))))

    (: repeated-capture (impl (Fn Identifier (List (List Capture)) -> Capture)))
    (define (repeated-capture variable repeats)
      (Capture variable (Many (map (lambda (captures) (captured captures variable)) repeats))))

    ;; What one repetition bound `variable` to. Each repetition matched the
    ;; repeated pattern, and a pattern binds every one of its variables.
    (: captured (impl (Fn (List Capture) Identifier -> Bound)))
    (define (captured captures variable)
      (match (find (lambda (capture) (same-identifier? (::variable capture) variable)) captures)
        ((Some capture) (::bound capture))
        ((None) (panic "internal error: a repetition did not bind its pattern's variable"))))

    (: malformed-literal (impl (Fn Marked -> Matching)))
    (define (malformed-literal literal)
      (MalformedLiteral (marked-loc literal) "expected an identifier"))

    (: literal-problem? (impl (Fn Matching -> Bool)))
    (define (literal-problem? matching)
      (match matching
        ((MalformedLiteral _ _) #t)
        (_ #f)))

    ;; The pattern variables of a pattern, in order: each identifier but
    ;; `_`, `...` and a literal.
    (: pattern-variables (impl (Fn (List Marked) Marked -> (Result (List Identifier) Marked))))
    (define (pattern-variables literals pattern)
      (match pattern
        ((Ident identifier _)
         (if (or (string=? (::name identifier) "_") (string=? (::name identifier) "..."))
             (Ok (Nil))
             (match (literal-check literals identifier)
               ((NotLiteral) (Ok (list identifier)))
               ((IsLiteral) (Ok (Nil)))
               ((BadLiteral literal) (Err literal)))))
        ((Form items _)
         (let loop ((items items)
                    (found (Nil)))
           (match items
             ((Nil) (Ok (concatenate (reverse found))))
             ((Cons item rest)
              (match (pattern-variables literals item)
                ((Ok variables) (loop rest (Cons variables found)))
                ((Err literal) (Err literal)))))))
        (_ (Ok (Nil)))))

    ;; ---- Literals ----

    ;; Whether an identifier of a pattern is one of the literals, looked
    ;; for in order: a literal that is not an identifier, met before the
    ;; identifier is found, is the answer.
    (enum LiteralCheck
      (IsLiteral)
      (NotLiteral)
      (BadLiteral
       ((literal Marked))))

    (: literal-check (impl (Fn (List Marked) Identifier -> LiteralCheck)))
    (define (literal-check literals identifier)
      (match literals
        ((Nil) (NotLiteral))
        ((Cons (Ident literal _) rest)
         (if (same-identifier? literal identifier) (IsLiteral) (literal-check rest identifier)))
        ((Cons literal _) (BadLiteral literal))))

    ;; A use's identifier matches a literal when both mean the same, or
    ;; when neither is bound and their names are the same.
    (: same-binding? (impl (Fn Matcher Marked Identifier -> Bool)))
    (define (same-binding? matcher input literal)
      (match input
        ((Ident identifier _)
         (match (Pair (resolve (::scopes matcher) (::use matcher) identifier)
                      (resolve (::scopes matcher) (::definition matcher) literal))
           ((Pair (Unbound) (Unbound)) (string=? (::name identifier) (::name literal)))
           ((Pair resolution other) (same-resolution? resolution other))))
        (_ #f)))

    ;; ---- Atoms ----

    (: same-datum? (impl (Fn Datum Datum -> Bool)))
    (define (same-datum? datum other)
      (match (Pair datum other)
        ((Pair (datum-Integer a) (datum-Integer b)) (= a b))
        ((Pair (datum-Float a) (datum-Float b)) (string=? a b))
        ((Pair (datum-Text a) (datum-Text b)) (string=? a b))
        ((Pair (datum-Character a) (datum-Character b)) (char=? a b))
        ((Pair (datum-ByteVector a) (datum-ByteVector b)) (same-bytes? a b))
        ((Pair (datum-Boolean a) (datum-Boolean b)) (if a b (not b)))
        (_ #f)))

    (: same-bytes? (impl (Fn Bytes Bytes -> Bool)))
    (define (same-bytes? bytes other)
      (and (= (vector-length bytes) (vector-length other))
           (let loop ((index 0))
             (or (= index (vector-length bytes))
                 (and (= (u8->i32 (vector-ref bytes index)) (u8->i32 (vector-ref other index)))
                      (loop (+ index 1)))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-syntax-rules)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail core table)
     (snail compiler expand language)
     (only (snail compiler names globals) Local Global TopGlobal)
     (snail compiler expand offer)
     (snail stage0 testing))
    (begin
      (define (test-syntax-rules)
        (test-macro-shapes)
        (test-rule-forms)
        (test-patterns)
        (test-literals)
        (test-ellipses)
        (test-bad-literals))

      ;; ---- Helpers ----

      (define loc (Loc "t.sld" 1 1))

      (define main (list "main"))

      ;; Marked syntax for quoted data, all at `loc`, with no marks.
      (define (marked datum)
        (cond ((or (null? datum) (pair? datum)) (Form (map marked datum) loc))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) loc))
              ((string? datum) (Atom (datum-Text datum) loc))
              ((exact-integer? datum) (Atom (datum-Integer datum) loc))
              ((boolean? datum) (Atom (datum-Boolean datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (plain name)
        (Identifier name (Nil)))

      ;; A top level binding `else` to a keyword and `x` to a value.
      (define here
        (TopScope (table-set (table-set empty-table
                                        "else"
                                        (list (Binding (plain "else") (Keyword "else"))))
                             "x"
                             (list (Binding (plain "x") (Value (TopGlobal (Global main "x" 0))))))
                  empty-table))

      (define scopes
        (Scopes main here (list)))

      (define top
        (Env (list) main))

      (define (matcher literals)
        (Matcher (map marked literals) scopes top top))

      ;; Whether `pattern`, a rule's patterns, matches `use`, the items
      ;; after a use's head.
      (define (matching literals pattern use)
        (match-rule (matcher literals) (map marked pattern) (map marked use)))

      (define (one name datum)
        (Capture (plain name) (One (marked datum))))

      ;; ---- Cases ----

      (define (test-macro-shapes)
        (expect (macro-shape (marked '(define-syntax m (syntax-rules (else) ((_ x) x)))))
                (WellFormedMacro
                 (MacroForm (plain "m") loc (list (marked 'else)) (list (marked '((_ x) x))))))
        (expect (macro-shape (marked '(define-syntax m (syntax-rules ()))))
                (WellFormedMacro (MacroForm (plain "m") loc (list) (list))))
        (expect (macro-shape (marked '(define-syntax m (syntax-rules x)))) not-syntax-rules)
        (expect (macro-shape (marked '(define-syntax m (rules ())))) not-syntax-rules)
        (expect (macro-shape (marked '(define-syntax m))) not-syntax-rules)
        (expect (macro-shape (marked '(define-syntax m (syntax-rules ()) extra))) not-syntax-rules)
        (expect (macro-shape (Form (list (marked 'define-syntax)
                                         (Atom (datum-Integer 1) (Loc "t.sld" 2 2))
                                         (marked '(syntax-rules ())))
                                   loc))
                (MalformedMacro (Loc "t.sld" 2 2) "expected a macro name")))

      (define not-syntax-rules
        (MalformedMacro loc "expected (define-syntax name (syntax-rules (literal ...) rule ...))"))

      (define (test-rule-forms)
        (expect (rule-form (marked '((_ a b) (a b))))
                (Ok (RuleForm (list (marked 'a) (marked 'b)) (marked '(a b)))))
        (expect (rule-form (marked '((m) 1))) (Ok (RuleForm (list) (marked 1))))
        (expect (rule-form (marked '(() 1))) (Err "expected ((_ pattern ...) template)"))
        (expect (rule-form (marked '(_ 1))) (Err "expected ((_ pattern ...) template)"))
        (expect (rule-form (marked '((_) 1 2))) (Err "expected ((_ pattern ...) template)"))
        (expect (rule-form (marked 'x)) (Err "expected ((_ pattern ...) template)")))

      ;; Variables capture in order; `_` and atoms capture nothing; a form
      ;; must have as many items as its pattern.
      (define (test-patterns)
        (expect (matching '() '(a (b _) 3) '(1 (x y) 3))
                (Matched (list (one "a" 1) (one "b" 'x))))
        (expect (matching '() '(a) '((f x))) (Matched (list (one "a" '(f x)))))
        (expect (matching '() '(a b) '(1)) (Mismatched))
        (expect (matching '() '(a) '(1 2)) (Mismatched))
        (expect (matching '() '(3) '(4)) (Mismatched))
        (expect (matching '() '("s") '("s")) (Matched (list)))
        (expect (matching '() '((a)) '(a)) (Mismatched))
        (expect (matching '() '() '()) (Matched (list))))

      ;; A literal matches an identifier with its binding, or with its name
      ;; when both are unbound; a pattern identifier is a literal only
      ;; with the literal's marks.
      (define (test-literals)
        (let* ((x (Local "else" 1))
               (shadowed (Env (list (Frame (plain "else") (LocalValue x))) main))
               (marked-else (Identifier "else" (list (Mark main 9 (TopLevel main))))))
          (expect (matching '(else) '(else) '(else)) (Matched (list)))
          (expect (matching '(else) '(else) '(x)) (Mismatched))
          (expect (matching '(unbound) '(unbound) '(unbound)) (Matched (list)))
          (expect (matching '(unbound) '(unbound) '(other)) (Mismatched))
          (expect (matching '(else) '(else) '(1)) (Mismatched))
          (expect (match-rule (Matcher (list (marked 'else)) scopes shadowed top)
                              (list (marked 'else))
                              (list (marked 'else)))
                  (Mismatched))
          (expect
           (match-rule (matcher '(else)) (list (marked 'else)) (list (Ident marked-else loc)))
           (Matched (list)))
          (expect (match-rule (matcher '(else))
                              (list (Ident marked-else loc))
                              (list (marked 'x)))
                  (Matched (list (Capture marked-else (One (marked 'x))))))))

      ;; A repeated pattern takes what the patterns after it leave, and
      ;; binds each of its variables to every repetition's match.
      (define (test-ellipses)
        (expect (matching '() '(a ... z) '(1 2 3))
                (Matched (list (Capture (plain "a") (Many (list (One (marked 1)) (One (marked 2)))))
                               (one "z" 3))))
        (expect (matching '() '(a ...) '())
                (Matched (list (Capture (plain "a") (Many (list))))))
        (expect (matching '() '(a ... y z) '(1)) (Mismatched))
        (expect (matching '() '((k v) ...) '((1 2) (3 4)))
                (Matched (list (Capture (plain "k") (Many (list (One (marked 1)) (One (marked 3)))))
                               (Capture (plain "v")
                                        (Many (list (One (marked 2)) (One (marked 4))))))))
        (expect (matching '() '((k v) ...) '((1 2) 3)) (Mismatched))
        (expect (matching '() '((a ...) ...) '((1 2) ()))
                (Matched (list (Capture (plain "a")
                                        (Many (list (Many (list (One (marked 1)) (One (marked 2))))
                                                    (Many (list))))))))
        (expect (matching '(else) '((else a) ...) '((else 1)))
                (Matched (list (Capture (plain "a") (Many (list (One (marked 1)))))))))

      ;; A literal that is not an identifier is met as the old expander
      ;; met it: only when an identifier of a pattern is compared with the
      ;; literals before it; then it is the answer, even past a mismatch in
      ;; another repetition.
      (define (test-bad-literals)
        (let ((bad (Atom (datum-Integer 5) (Loc "t.sld" 3 3))))
          (define (with-bad pattern use)
            (match-rule (Matcher (list (marked 'else) bad) scopes top top)
                        (map marked pattern)
                        (map marked use)))
          (expect (with-bad '(a) '(1))
                  (MalformedLiteral (Loc "t.sld" 3 3) "expected an identifier"))
          (expect (with-bad '(else) '(else)) (Matched (list)))
          (expect (with-bad '(_ 1) '(2 1)) (Matched (list)))
          (expect (with-bad '(1 a) '(2 3)) (Mismatched))
          (expect (with-bad '(1 ...) '()) (Matched (list)))
          (expect (with-bad '(a ...) '())
                  (MalformedLiteral (Loc "t.sld" 3 3) "expected an identifier"))
          (expect (with-bad '((1 a) ...) '((2 3) (1 4)))
                  (MalformedLiteral (Loc "t.sld" 3 3) "expected an identifier"))
          (expect (with-bad '((1 else) ...) '((1 else) (2 else))) (Mismatched))))))
   (else)))
