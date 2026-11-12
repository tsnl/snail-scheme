;; Scheme to Snail-Core: R7RS source text becomes the syntax of a Snail-Core library
;; whose top level runs the program. Every value is an Any and every
;; variable a cell holding one, named with a leading `%` so no Scheme name
;; meets a Snail-Core one; (scheme runtime) supplies the standard procedures. A
;; recipe runs the translator when a library is built:
;;
;;   (generate-library (legacy hello)
;;                     (import (snail core base) (snail core io) (scheme compiler))
;;                     (scheme->snail-core-library (list "legacy" "hello") (read-file "hello.scm")))
;;
;; The supported forms are define, lambda (with rest parameters), if, set!,
;; quote, let (and named let), let*, letrec, letrec*, begin, cond (with
;; `else` and `=>`), case, and, or, when and unless. Macros, quasiquote,
;; continuations and mutable pairs are not supported.
(define-library (scheme compiler)
  (export
   scheme->snail-core-library)
  (import
   (snail core base)
   (snail shell number)
   (snail shell datum)
   (snail shell read)
   (snail shell write)
   (snail shell syntax))
  (begin

    ;; ---- Programs ----

    (define (scheme->snail-core-library (name (List String)) (source String)) (→ Syntax)
      (match (read-datums source)
        ((Ok forms)
         (library-syntax name
                         (Nil)
                         (list (list "snail" "core" "base")
                               (list "snail" "shell" "datum")
                               (list "scheme" "runtime"))
                         (map translate-top forms)))
        ((Err message) (panic (string-append "scheme: " message)))))

    ;; A top-level definition is a cell; any other form runs at startup.
    (define (translate-top (top Any)) (→ Syntax)
      (match (definition top)
        ((Some (Pair name value))
         (form "define" (list (variable name) (form "Variable" (list (evaluation (translate value)))))))
        ((None) (evaluation (translate top)))))

    ;; A generated script installs its failure boundary explicitly. Runtime
    ;; calls themselves retain dyn-cast so a typed caller may catch failures.
    (define (evaluation (expression Syntax)) (→ Syntax)
      (form "scheme-evaluate" (list (form "lambda" (list (ListSyntax (Nil)) expression)))))

    (define (definition (top Any)) (→ (Option (Pair String Any)))
      (match (datum->list top)
        ((Some (Cons keyword (Cons target body)))
         (if (symbol-is? keyword "define") (Some (definition-parts target body)) (None)))
        (_ (None))))

    (define (definition-parts (target Any) (body (List Any))) (→ (Pair String Any))
      (match-any target
                 ((Symbol (Symbol name))
                  (match body
                    ((Cons value (Nil)) (Pair name value))
                    (_ (panic "scheme: expected (define name value)"))))
                 ((SchemePair (SchemePair name params))
                  (Pair (symbol-name name)
                        (datum-list (Cons (ann (Symbol "lambda") Any) (Cons params body)))))
                 (else (panic "scheme: expected a definition name"))))

    (define (variable (name String)) (→ Syntax)
      (SymbolSyntax (string-append "%" name)))

    (define unspecified (SymbolSyntax "unspecified"))

    ;; `(if test yes no)` where Scheme's truth decides: anything but #f.
    (define (scheme-if (test Syntax) (yes Syntax) (no Syntax)) (→ Syntax)
      (form "if" (list (form "datum-truthy?" (list test)) yes no)))

    ;; ---- Expressions ----

    (define (translate (datum Any)) (→ Syntax)
      (match-any datum
                 ((Symbol (Symbol name)) (form "Variable-value" (list (variable name))))
                 ((SchemePair (SchemePair head rest))
                  (match-any head
                             ((Symbol (Symbol keyword))
                              (if (member? keyword special-forms)
                                  (translate-special keyword (items rest))
                                  (translate-call datum)))
                             (else (translate-call datum))))
                 (else (quoted datum))))

    (define special-forms (→ (List String))
      (list "quote"
            "lambda"
            "if"
            "set!"
            "let"
            "let*"
            "letrec"
            "letrec*"
            "begin"
            "cond"
            "case"
            "and"
            "or"
            "when"
            "unless"))

    (define (translate-call (datum Any)) (→ Syntax)
      (match (items datum)
        ((Cons f arguments)
         (form "call" (list (translate f) (form "list" (map translate arguments)))))
        ((Nil) (panic "scheme: empty application"))))

    (define (translate-special (keyword String) (args (List Any))) (→ Syntax)
      (case keyword
        (("quote") (quoted (first args)))
        (("lambda") (translate-lambda (first args) (list-tail args 1)))
        (("if") (translate-if args))
        (("set!")
         (form "begin"
               (list (form "Variable-value-set!"
                           (list (variable (symbol-name (first args))) (translate (second args))))
                     unspecified)))
        (("let") (translate-let args))
        (("let*") (translate-let* (items (first args)) (list-tail args 1)))
        (("letrec" "letrec*") (translate-letrec (items (first args)) (list-tail args 1)))
        (("begin") (if (null? args) unspecified (form "begin" (map translate args))))
        (("cond") (translate-cond args))
        (("case") (translate-case (first args) (list-tail args 1)))
        (("and") (translate-and args))
        (("or") (translate-or args))
        (("when")
         (scheme-if (translate (first args)) (translate-body (list-tail args 1)) unspecified))
        (("unless")
         (scheme-if (translate (first args)) unspecified (translate-body (list-tail args 1))))
        (else (panic (string-append "scheme: unsupported form " keyword)))))

    (define (translate-if (args (List Any))) (→ Syntax)
      (match args
        ((Cons test (Cons then (Nil))) (scheme-if (translate test) (translate then) unspecified))
        ((Cons test (Cons then (Cons otherwise (Nil))))
         (scheme-if (translate test) (translate then) (translate otherwise)))
        (_ (panic "scheme: expected (if test then [else])"))))

    ;; ---- Procedures and bodies ----

    ;; Construction proves every parameter is a distinct symbol. Both the
    ;; arity check and the bindings consume this same source-ordered value.
    (struct Parameters
      ((fixed (List String))
       (rest (Option String))))

    (define (parse-parameters (datum Any)) (→ Parameters)
      (let loop ((tail datum) (fixed (ann (Nil) (List String))))
        (match-any tail
                   ((Null _) (Parameters (reverse fixed) (None)))
                   ((Symbol (Symbol name)) (Parameters (reverse fixed) (Some (fresh name fixed))))
                   ((SchemePair (SchemePair name rest))
                    (match-any name
                               ((Symbol (Symbol name)) (loop rest (Cons (fresh name fixed) fixed)))
                               (else (panic "scheme: expected parameter names"))))
                   (else (panic "scheme: expected parameter names")))))

    (define (fresh (name String) (bound (List String))) (→ String)
      (if (member? name bound) (panic "scheme: duplicate parameter") name))

    ;; A procedure takes its arguments as one list and checks their count.
    (define (translate-lambda (datum Any) (body (List Any))) (→ Syntax)
      (let ((params (parse-parameters datum)) (arguments (SymbolSyntax "arguments")))
        (boxed (form "Procedure"
                     (list (form "lambda"
                                 (list (ListSyntax (list arguments))
                                       (form "arity!"
                                             (list arguments
                                                   (IntegerSyntax
                                                    (length (● params fixed)))
                                                   (BooleanSyntax (match (● params rest)
                                                                    ((Some _) #t)
                                                                    ((None) #f)))))
                                       (form "let"
                                             (list (ListSyntax (parameter-cells params arguments))
                                                   (translate-body body))))))))))

    ;; Fixed parameters take the arguments' first items, and a rest
    ;; parameter the remainder.
    (define (parameter-cells (params Parameters) (arguments Syntax)) (→ (List Syntax))
      (let ((fixed (● params fixed)))
        (append (map-indexed (lambda (index name)
                               (cell name (form "list-ref" (list arguments (IntegerSyntax index)))))
                             fixed)
                (match (● params rest)
                  ((Some name)
                   (list (cell name
                               (form "rest-arguments"
                                     (list arguments (IntegerSyntax (length fixed)))))))
                  ((None) (Nil))))))

    ;; `(%name (ref value))`, a binding of a variable's cell.
    (define (cell (name String) (value Syntax)) (→ Syntax)
      (ListSyntax (list (variable name) (form "Variable" (list value)))))

    (define (empty-cells (names (List String))) (→ (List Syntax))
      (map (lambda (name) (cell name unspecified)) names))

    ;; Internal definitions become cells that all exist before any is set,
    ;; so they may refer to each other, as with letrec*.
    (define (translate-body (body (List Any))) (→ Syntax)
      (let ((names (concatenate (map (lambda (item)
                                       (match (definition item)
                                         ((Some (Pair name _)) (list name))
                                         ((None) (Nil))))
                                     body))))
        (form "let" (Cons (ListSyntax (empty-cells names))
                          (map (lambda (item)
                                 (match (definition item)
                                   ((Some (Pair name value))
                                    (form "Variable-value-set!" (list (variable name) (translate value))))
                                   ((None) (translate item))))
                               body)))))

    ;; ---- Binding forms ----

    (define (translate-let (args (List Any))) (→ Syntax)
      (match args
        ((Cons first rest)
         (match-any first
                    ((Symbol (Symbol name))
                     (match rest
                       ((Cons bindings body)
                        (translate-named-let name (map binding (items bindings)) body))
                       (_ (panic "scheme: expected named let bindings"))))
                    (else (form "let"
                                (list (ListSyntax
                                       (map (lambda (pair)
                                              (cell (● pair first)
                                                    (translate (● pair second))))
                                            (map binding (items first))))
                                      (translate-body rest))))))
        (_ (panic "scheme: expected (let ((name value) ...) body ...)"))))

    (define (translate-named-let (name String) (pairs (List (Pair String Any))) (body (List Any)))
      (→ Syntax)
      (let ((procedure (translate-lambda
                        (datum-list
                         (map (lambda (pair) (ann (Symbol (● pair first)) Any)) pairs))
                        body)))
        (form "let" (list (ListSyntax (empty-cells (list name)))
                          (form "Variable-value-set!" (list (variable name) procedure))
                          (form "call"
                                (list (form "Variable-value" (list (variable name)))
                                      (form "list"
                                            (map translate
                                                 (map (lambda (record) (● record second))
                                                      pairs)))))))))

    (define (translate-let* (bindings (List Any)) (body (List Any))) (→ Syntax)
      (match bindings
        ((Nil) (translate-body body))
        ((Cons first rest)
         (let ((pair (binding first)))
           (form "let"
                 (list (ListSyntax (list (cell (● pair first) (translate (● pair second)))))
                       (translate-let* rest body)))))))

    (define (translate-letrec (bindings (List Any)) (body (List Any))) (→ Syntax)
      (let ((pairs (map binding bindings)))
        (form "let" (Cons (ListSyntax (empty-cells (map (lambda (record) (● record first)) pairs)))
                          (append (map (lambda (pair)
                                         (form "Variable-value-set!"
                                               (list (variable (● pair first))
                                                     (translate (● pair second)))))
                                       pairs)
                                  (list (translate-body body)))))))

    (define (binding (datum Any)) (→ (Pair String Any))
      (match (datum->list datum)
        ((Some (Cons name (Cons value (Nil)))) (Pair (symbol-name name) value))
        (_ (panic (string-append "scheme: expected (name value), got " (datum->string datum))))))

    (define (holding (name String) (value Syntax) (body (Fn Syntax → Syntax))) (→ Syntax)
      (let ((held (SymbolSyntax name)))
        (form "let" (list (ListSyntax (list (ListSyntax (list held value)))) (body held)))))

    (define (translate-and (args (List Any))) (→ Syntax)
      (match args
        ((Nil) (boxed (BooleanSyntax #t)))
        ((Cons last (Nil)) (translate last))
        ((Cons first rest)
         (holding "and.value"
                  (translate first)
                  (lambda (value) (scheme-if value (translate-and rest) value))))))

    (define (translate-or (args (List Any))) (→ Syntax)
      (match args
        ((Nil) (boxed (BooleanSyntax #f)))
        ((Cons last (Nil)) (translate last))
        ((Cons first rest)
         (holding "or.value"
                  (translate first)
                  (lambda (value) (scheme-if value value (translate-or rest)))))))

    (define (translate-cond (clauses (List Any))) (→ Syntax)
      (match clauses
        ((Nil) unspecified)
        ((Cons clause rest) (translate-clause (items clause) (translate-cond rest)))))

    ;; One clause of a `cond`, given what the clauses after it do.
    (define (translate-clause (clause (List Any)) (otherwise Syntax)) (→ Syntax)
      (match clause
        ((Cons test body)
         (if (symbol-is? test "else") (translate-body body)
             (holding "cond.value" (translate test)
                      (lambda (value) (scheme-if value (cond-value value body) otherwise)))))
        ((Nil) (panic "scheme: empty cond clause"))))

    (define (cond-value (value Syntax) (body (List Any))) (→ Syntax)
      (match body
        ((Nil) value)
        ((Cons arrow (Cons receiver (Nil)))
         (if (symbol-is? arrow "=>")
             (form "call" (list (translate receiver) (form "list" (list value))))
             (translate-body body)))
        (_ (translate-body body))))

    (define (translate-case (key Any) (clauses (List Any))) (→ Syntax)
      (holding "case.key" (translate key) (lambda (held) (case-clauses held clauses))))

    (define (case-clauses (key Syntax) (clauses (List Any))) (→ Syntax)
      (match clauses
        ((Nil) unspecified)
        ((Cons clause rest)
         (match (items clause)
           ((Cons data body)
            (if (symbol-is? data "else") (translate-body body)
                (form "if" (list (form "member-datum?" (list key (quoted data)))
                                 (translate-body body) (case-clauses key rest)))))
           ((Nil) (panic "scheme: empty case clause"))))))

    ;; ---- Data ----

    ;; Only the outer boundary is erased; native literal types survive until
    ;; they enter a Scheme value, pair field, vector element or mutable cell.
    (define (boxed (expression Syntax)) (→ Syntax)
      (form "ann" (list expression (SymbolSyntax "Any"))))

    (define (quoted (datum Any)) (→ Syntax)
      (boxed
       (match-any datum
                  ((Null _) (form "Null" (Nil)))
                  ((Bool value) (BooleanSyntax value))
                  ((Char char) (CharSyntax char))
                  ((String text) (StringSyntax text))
                  ((Symbol (Symbol name)) (form "Symbol" (list (StringSyntax name))))
                  ((SchemePair (SchemePair head tail))
                   (form "SchemePair" (list (quoted head) (quoted tail))))
                  (((Vector Any) elements)
                   (form "list->vector"
                         (list (form "ann" (list (form "list" (map quoted (vector->list elements)))
                                                 (form "List" (list (SymbolSyntax "Any"))))))))
                  ((Bytes bytes) (BytesSyntax bytes))
                  (else (match (datum-number datum)
                          ((Some n) (form "scheme-number" (list (StringSyntax (number->string n)))))
                          ((None) (panic "scheme: this value cannot be quoted")))))))

    ;; ---- Lists of syntax ----

    (define (items (datum Any)) (→ (List Any))
      (match (datum->list datum)
        ((Some elements) elements)
        ((None) (panic (string-append "scheme: expected a list, got " (datum->string datum))))))

    (define (first (data (List Any))) (→ Any)
      (match data
        ((Cons datum _) datum)
        ((Nil) (panic "scheme: a form is missing a part"))))

    (define (second (data (List Any))) (→ Any)
      (first (list-tail data 1)))

    (define (symbol-name (datum Any)) (→ String)
      (match-any datum
                 ((Symbol (Symbol name)) name)
                 (else
                  (panic (string-append "scheme: expected a symbol, got " (datum->string datum))))))

    (define (symbol-is? (datum Any) (name String)) (→ Bool)
      (match-any datum ((Symbol (Symbol actual)) (string=? name actual)) (else #f)))

    ))
