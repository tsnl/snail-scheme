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

    (: scheme->snail-core-library (-> (List String) String Syntax))
    (define (scheme->snail-core-library name source)
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
    (: translate-top (-> Any Syntax))
    (define (translate-top top)
      (match (definition top)
        ((Some (Pair name value))
         (form "define" (list (variable name) (form "ref" (list (evaluation (translate value)))))))
        ((None) (evaluation (translate top)))))

    ;; A generated script installs its failure boundary explicitly. Runtime
    ;; calls themselves retain dyn-cast so a typed caller may catch failures.
    (: evaluation (-> Syntax Syntax))
    (define (evaluation expression)
      (form "scheme-evaluate" (list (form "lambda" (list (ListSyntax (Nil)) expression)))))

    (: definition (-> Any (Option (Pair String Any))))
    (define (definition top)
      (match (datum->list top)
        ((Some (Cons keyword (Cons target body)))
         (if (symbol-is? keyword "define") (Some (definition-parts target body)) (None)))
        (_ (None))))

    (: definition-parts (-> Any (List Any) (Pair String Any)))
    (define (definition-parts target body)
      (match-any target
                 ((Symbol (Symbol name))
                  (match body
                    ((Cons value (Nil)) (Pair name value))
                    (_ (panic "scheme: expected (define name value)"))))
                 ((SchemePair (SchemePair name params))
                  (Pair (symbol-name name)
                        (datum-list (Cons (ann (Symbol "lambda") Any) (Cons params body)))))
                 (else (panic "scheme: expected a definition name"))))

    (: variable (-> String Syntax))
    (define (variable name)
      (SymbolSyntax (string-append "%" name)))

    (define unspecified (SymbolSyntax "unspecified"))

    ;; `(if test yes no)` where Scheme's truth decides: anything but #f.
    (: scheme-if (-> Syntax Syntax Syntax Syntax))
    (define (scheme-if test yes no)
      (form "if" (list (form "datum-truthy?" (list test)) yes no)))

    ;; ---- Expressions ----

    (: translate (-> Any Syntax))
    (define (translate datum)
      (match-any datum
                 ((Symbol (Symbol name)) (form "ref-get" (list (variable name))))
                 ((SchemePair (SchemePair head rest))
                  (match-any head
                             ((Symbol (Symbol keyword))
                              (if (member? keyword special-forms)
                                  (translate-special keyword (items rest))
                                  (translate-call datum)))
                             (else (translate-call datum))))
                 (else (quoted datum))))

    (: special-forms (List String))
    (define special-forms
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

    (: translate-call (-> Any Syntax))
    (define (translate-call datum)
      (match (items datum)
        ((Cons f arguments)
         (form "call" (list (translate f) (form "list" (map translate arguments)))))
        ((Nil) (panic "scheme: empty application"))))

    (: translate-special (-> String (List Any) Syntax))
    (define (translate-special keyword args)
      (case keyword
        (("quote") (quoted (first args)))
        (("lambda") (translate-lambda (first args) (list-tail args 1)))
        (("if") (translate-if args))
        (("set!")
         (form "begin"
               (list (form "ref-set!"
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

    (: translate-if (-> (List Any) Syntax))
    (define (translate-if args)
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

    (: parse-parameters (-> Any Parameters))
    (define (parse-parameters datum)
      (let loop ((tail datum) (fixed (ann (Nil) (List String))))
        (match-any tail
                   ((Null _) (Parameters (reverse fixed) (None)))
                   ((Symbol (Symbol name)) (Parameters (reverse fixed) (Some (fresh name fixed))))
                   ((SchemePair (SchemePair name rest))
                    (match-any name
                               ((Symbol (Symbol name)) (loop rest (Cons (fresh name fixed) fixed)))
                               (else (panic "scheme: expected parameter names"))))
                   (else (panic "scheme: expected parameter names")))))

    (: fresh (-> String (List String) String))
    (define (fresh name bound)
      (if (member? name bound) (panic "scheme: duplicate parameter") name))

    ;; A procedure takes its arguments as one list and checks their count.
    (: translate-lambda (-> Any (List Any) Syntax))
    (define (translate-lambda datum body)
      (let ((params (parse-parameters datum)) (arguments (SymbolSyntax "arguments")))
        (boxed (form "Procedure"
                     (list (form "lambda"
                                 (list (ListSyntax (list arguments))
                                       (form "arity!"
                                             (list arguments
                                                   (IntegerSyntax
                                                    (length (Parameters-fixed params)))
                                                   (BooleanSyntax (match (Parameters-rest params)
                                                                    ((Some _) #t)
                                                                    ((None) #f)))))
                                       (form "let"
                                             (list (ListSyntax (parameter-cells params arguments))
                                                   (translate-body body))))))))))

    ;; Fixed parameters take the arguments' first items, and a rest
    ;; parameter the remainder.
    (: parameter-cells (-> Parameters Syntax (List Syntax)))
    (define (parameter-cells params arguments)
      (let ((fixed (Parameters-fixed params)))
        (append (map-indexed (lambda (index name)
                               (cell name (form "list-ref" (list arguments (IntegerSyntax index)))))
                             fixed)
                (match (Parameters-rest params)
                  ((Some name)
                   (list (cell name
                               (form "rest-arguments"
                                     (list arguments (IntegerSyntax (length fixed)))))))
                  ((None) (Nil))))))

    ;; `(%name (ref value))`, a binding of a variable's cell.
    (: cell (-> String Syntax Syntax))
    (define (cell name value)
      (ListSyntax (list (variable name) (form "ref" (list value)))))

    (: empty-cells (-> (List String) (List Syntax)))
    (define (empty-cells names)
      (map (lambda (name) (cell name unspecified)) names))

    ;; Internal definitions become cells that all exist before any is set,
    ;; so they may refer to each other, as with letrec*.
    (: translate-body (-> (List Any) Syntax))
    (define (translate-body body)
      (let ((names (concatenate (map (lambda (item)
                                       (match (definition item)
                                         ((Some (Pair name _)) (list name))
                                         ((None) (Nil))))
                                     body))))
        (form "let" (Cons (ListSyntax (empty-cells names))
                          (map (lambda (item)
                                 (match (definition item)
                                   ((Some (Pair name value))
                                    (form "ref-set!" (list (variable name) (translate value))))
                                   ((None) (translate item))))
                               body)))))

    ;; ---- Binding forms ----

    (: translate-let (-> (List Any) Syntax))
    (define (translate-let args)
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
                                              (cell (Pair-first pair)
                                                    (translate (Pair-second pair))))
                                            (map binding (items first))))
                                      (translate-body rest))))))
        (_ (panic "scheme: expected (let ((name value) ...) body ...)"))))

    (: translate-named-let (-> String (List (Pair String Any)) (List Any) Syntax))
    (define (translate-named-let name pairs body)
      (let ((procedure (translate-lambda
                        (datum-list
                         (map (lambda (pair) (ann (Symbol (Pair-first pair)) Any)) pairs))
                        body)))
        (form "let" (list (ListSyntax (empty-cells (list name)))
                          (form "ref-set!" (list (variable name) procedure))
                          (form "call"
                                (list (form "ref-get" (list (variable name)))
                                      (form "list" (map translate (map Pair-second pairs)))))))))

    (: translate-let* (-> (List Any) (List Any) Syntax))
    (define (translate-let* bindings body)
      (match bindings
        ((Nil) (translate-body body))
        ((Cons first rest)
         (let ((pair (binding first)))
           (form "let"
                 (list (ListSyntax (list (cell (Pair-first pair) (translate (Pair-second pair)))))
                       (translate-let* rest body)))))))

    (: translate-letrec (-> (List Any) (List Any) Syntax))
    (define (translate-letrec bindings body)
      (let ((pairs (map binding bindings)))
        (form "let" (Cons (ListSyntax (empty-cells (map Pair-first pairs)))
                          (append (map (lambda (pair)
                                         (form "ref-set!"
                                               (list (variable (Pair-first pair))
                                                     (translate (Pair-second pair)))))
                                       pairs)
                                  (list (translate-body body)))))))

    (: binding (-> Any (Pair String Any)))
    (define (binding datum)
      (match (datum->list datum)
        ((Some (Cons name (Cons value (Nil)))) (Pair (symbol-name name) value))
        (_ (panic (string-append "scheme: expected (name value), got " (datum->string datum))))))

    (: holding (-> String Syntax (-> Syntax Syntax) Syntax))
    (define (holding name value body)
      (let ((held (SymbolSyntax name)))
        (form "let" (list (ListSyntax (list (ListSyntax (list held value)))) (body held)))))

    (: translate-and (-> (List Any) Syntax))
    (define (translate-and args)
      (match args
        ((Nil) (boxed (BooleanSyntax #t)))
        ((Cons last (Nil)) (translate last))
        ((Cons first rest)
         (holding "and.value"
                  (translate first)
                  (lambda (value) (scheme-if value (translate-and rest) value))))))

    (: translate-or (-> (List Any) Syntax))
    (define (translate-or args)
      (match args
        ((Nil) (boxed (BooleanSyntax #f)))
        ((Cons last (Nil)) (translate last))
        ((Cons first rest)
         (holding "or.value"
                  (translate first)
                  (lambda (value) (scheme-if value value (translate-or rest)))))))

    (: translate-cond (-> (List Any) Syntax))
    (define (translate-cond clauses)
      (match clauses
        ((Nil) unspecified)
        ((Cons clause rest) (translate-clause (items clause) (translate-cond rest)))))

    ;; One clause of a `cond`, given what the clauses after it do.
    (: translate-clause (-> (List Any) Syntax Syntax))
    (define (translate-clause clause otherwise)
      (match clause
        ((Cons test body)
         (if (symbol-is? test "else") (translate-body body)
             (holding "cond.value" (translate test)
                      (lambda (value) (scheme-if value (cond-value value body) otherwise)))))
        ((Nil) (panic "scheme: empty cond clause"))))

    (: cond-value (-> Syntax (List Any) Syntax))
    (define (cond-value value body)
      (match body
        ((Nil) value)
        ((Cons arrow (Cons receiver (Nil)))
         (if (symbol-is? arrow "=>")
             (form "call" (list (translate receiver) (form "list" (list value))))
             (translate-body body)))
        (_ (translate-body body))))

    (: translate-case (-> Any (List Any) Syntax))
    (define (translate-case key clauses)
      (holding "case.key" (translate key) (lambda (held) (case-clauses held clauses))))

    (: case-clauses (-> Syntax (List Any) Syntax))
    (define (case-clauses key clauses)
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
    (: boxed (-> Syntax Syntax))
    (define (boxed expression)
      (form "ann" (list expression (SymbolSyntax "Any"))))

    (: quoted (-> Any Syntax))
    (define (quoted datum)
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

    (: items (-> Any (List Any)))
    (define (items datum)
      (match (datum->list datum)
        ((Some elements) elements)
        ((None) (panic (string-append "scheme: expected a list, got " (datum->string datum))))))

    (: first (-> (List Any) Any))
    (define (first data)
      (match data
        ((Cons datum _) datum)
        ((Nil) (panic "scheme: a form is missing a part"))))

    (: second (-> (List Any) Any))
    (define (second data)
      (first (list-tail data 1)))

    (: symbol-name (-> Any String))
    (define (symbol-name datum)
      (match-any datum
                 ((Symbol (Symbol name)) name)
                 (else
                  (panic (string-append "scheme: expected a symbol, got " (datum->string datum))))))

    (: symbol-is? (-> Any String Bool))
    (define (symbol-is? datum name)
      (match-any datum ((Symbol (Symbol actual)) (string=? name actual)) (else #f)))

    ))
