;; Scheme to Lofi: R7RS source text becomes the syntax of a Lofi library
;; whose top level runs the program. Every value is a Datum and every
;; variable a cell holding one, named with a leading `%` so no Scheme name
;; meets a Lofi one; (scheme runtime) supplies the standard procedures. A
;; recipe runs the translator when a library is built:
;;
;;   (generate-library (legacy hello)
;;                     (import (lofi base) (lofi io) (scheme compiler))
;;                     (scheme->lofi-library (list "legacy" "hello") (read-file "hello.scm")))
;;
;; The supported forms are define, lambda (with rest parameters), if, set!,
;; quote, let (and named let), let*, letrec, letrec*, begin, cond (with
;; `else` and `=>`), case, and, or, when and unless. Macros, quasiquote,
;; continuations and mutable pairs are not supported.
(define-library (scheme compiler)
  (export
   scheme->lofi-library)
  (import
   (lofi base)
   (lofi number)
   (lofi datum)
   (lofi read)
   (lofi write)
   (lofi syntax))
  (begin

    ;; ---- Programs ----

    (: scheme->lofi-library (-> (List String) String Syntax))
    (define (scheme->lofi-library name source)
      (match (read-datums source)
        ((Ok forms)
         (library-syntax name (Nil) (list (list "lofi" "base") (list "lofi" "datum") (list "scheme" "runtime"))
                         (map translate-top forms)))
        ((Err message) (panic (string-append "scheme: " message)))))

    ;; A top-level definition is a cell; any other form runs at startup.
    (: translate-top (-> Datum Syntax))
    (define (translate-top top)
      (match (definition top)
        ((Some (Pair name value)) (form "define" (list (variable name) (form "ref" (list (translate value))))))
        ((None) (translate top))))

    ;; `(define x e)` and `(define (f . params) body ...)` as a name and a value.
    (: definition (-> Datum (Option (Pair String Datum))))
    (define (definition top)
      (match top
        ((PairDatum (SymbolDatum "define") (PairDatum (SymbolDatum name) (PairDatum value (NullDatum))))
         (Some (Pair name value)))
        ((PairDatum (SymbolDatum "define") (PairDatum (PairDatum (SymbolDatum name) params) body))
         (Some (Pair name (PairDatum (SymbolDatum "lambda") (PairDatum params body)))))
        (_ (None))))

    (: variable (-> String Syntax))
    (define (variable name)
      (SymbolSyntax (string-append "%" name)))

    (define unspecified (SymbolSyntax "unspecified"))

    ;; `(if test yes no)` where Scheme's truth decides: anything but #f.
    (: scheme-if (-> Syntax Syntax Syntax Syntax))
    (define (scheme-if test yes no)
      (form "if" (list (form "datum-truthy?" (list test)) yes no)))

    ;; ---- Expressions ----

    (: translate (-> Datum Syntax))
    (define (translate datum)
      (match datum
        ((SymbolDatum name) (form "ref-get" (list (variable name))))
        ((PairDatum (SymbolDatum keyword) rest)
         (if (member? keyword special-forms) (translate-special keyword (items rest)) (translate-call datum)))
        ((PairDatum _ _) (translate-call datum))
        (_ (quoted datum))))

    (: special-forms (List String))
    (define special-forms
      (list "quote" "lambda" "if" "set!" "let" "let*" "letrec" "letrec*" "begin" "cond" "case" "and" "or" "when" "unless"))

    (: translate-call (-> Datum Syntax))
    (define (translate-call datum)
      (match (items datum)
        ((Cons f arguments) (form "call" (list (translate f) (form "list" (map translate arguments)))))
        ((Nil) (panic "scheme: empty application"))))

    (: translate-special (-> String (List Datum) Syntax))
    (define (translate-special keyword args)
      (case keyword
        (("quote") (quoted (first args)))
        (("lambda") (translate-lambda (first args) (list-tail args 1)))
        (("if") (translate-if args))
        (("set!") (form "begin" (list (form "ref-set!" (list (variable (symbol-name (first args))) (translate (second args)))) unspecified)))
        (("let") (translate-let args))
        (("let*") (translate-let* (items (first args)) (list-tail args 1)))
        (("letrec" "letrec*") (translate-letrec (items (first args)) (list-tail args 1)))
        (("begin") (if (null? args) unspecified (form "begin" (map translate args))))
        (("cond") (translate-cond args))
        (("case") (translate-case (first args) (list-tail args 1)))
        (("and") (translate-and args))
        (("or") (translate-or args))
        (("when") (scheme-if (translate (first args)) (translate-body (list-tail args 1)) unspecified))
        (("unless") (scheme-if (translate (first args)) unspecified (translate-body (list-tail args 1))))
        (else (panic (string-append "scheme: unsupported form " keyword)))))

    (: translate-if (-> (List Datum) Syntax))
    (define (translate-if args)
      (match args
        ((Cons test (Cons then (Nil))) (scheme-if (translate test) (translate then) unspecified))
        ((Cons test (Cons then (Cons otherwise (Nil)))) (scheme-if (translate test) (translate then) (translate otherwise)))
        (_ (panic "scheme: expected (if test then [else])"))))

    ;; ---- Procedures and bodies ----

    ;; Construction proves every parameter is a distinct symbol. Both the
    ;; arity check and the bindings consume this same source-ordered value.
    (struct Parameters
      ((fixed (List String))
       (rest (Option String))))

    (: parse-parameters (-> Datum Parameters))
    (define (parse-parameters datum)
      (let loop ((tail datum) (fixed (ann (Nil) (List String))))
        (match tail
          ((NullDatum) (Parameters (reverse fixed) (None)))
          ((SymbolDatum name)
           (if (member? name fixed) (panic "scheme: duplicate parameter") (Parameters (reverse fixed) (Some name))))
          ((PairDatum (SymbolDatum name) rest)
           (if (member? name fixed) (panic "scheme: duplicate parameter") (loop rest (Cons name fixed))))
          (_ (panic "scheme: expected parameter names")))))

    ;; A procedure takes its arguments as one list and checks their count.
    (: translate-lambda (-> Datum (List Datum) Syntax))
    (define (translate-lambda datum body)
      (let ((params (parse-parameters datum)) (arguments (SymbolSyntax "arguments")))
        (form "ProcedureDatum"
              (list (form "lambda"
                          (list (ListSyntax (list arguments))
                                (form "arity!" (list arguments (IntegerSyntax (length (Parameters-fixed params)))
                                                     (BooleanSyntax (match (Parameters-rest params) ((Some _) #t) ((None) #f)))))
                                (form "let" (list (ListSyntax (parameter-cells params arguments)) (translate-body body)))))))))

    ;; Fixed parameters take the arguments' first items, and a rest
    ;; parameter the remainder.
    (: parameter-cells (-> Parameters Syntax (List Syntax)))
    (define (parameter-cells params arguments)
      (let ((fixed (Parameters-fixed params)))
        (append (map-indexed (lambda (index name) (cell name (form "list-ref" (list arguments (IntegerSyntax index))))) fixed)
                (match (Parameters-rest params)
                  ((Some name) (list (cell name (form "rest-arguments" (list arguments (IntegerSyntax (length fixed)))))))
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
    (: translate-body (-> (List Datum) Syntax))
    (define (translate-body body)
      (let ((names (concatenate (map (lambda (item) (match (definition item) ((Some (Pair name _)) (list name)) ((None) (Nil)))) body))))
        (form "let" (Cons (ListSyntax (empty-cells names))
                          (map (lambda (item)
                                 (match (definition item)
                                   ((Some (Pair name value)) (form "ref-set!" (list (variable name) (translate value))))
                                   ((None) (translate item))))
                               body)))))

    ;; ---- Binding forms ----

    (: translate-let (-> (List Datum) Syntax))
    (define (translate-let args)
      (match args
        ((Cons (SymbolDatum name) (Cons bindings body)) (translate-named-let name (map binding (items bindings)) body))
        ((Cons bindings body)
         (form "let" (list (ListSyntax (map (lambda (pair) (cell (Pair-first pair) (translate (Pair-second pair)))) (map binding (items bindings))))
                           (translate-body body))))
        (_ (panic "scheme: expected (let ((name value) ...) body ...)"))))

    ;; A named let is a procedure in a cell of its own, called at once.
    (: translate-named-let (-> String (List (Pair String Datum)) (List Datum) Syntax))
    (define (translate-named-let name pairs body)
      (let ((procedure (translate-lambda (datum-list (map (lambda (pair) (SymbolDatum (Pair-first pair))) pairs)) body)))
        (form "let" (list (ListSyntax (empty-cells (list name)))
                          (form "ref-set!" (list (variable name) procedure))
                          (form "call" (list (form "ref-get" (list (variable name))) (form "list" (map translate (map Pair-second pairs)))))))))

    (: translate-let* (-> (List Datum) (List Datum) Syntax))
    (define (translate-let* bindings body)
      (match bindings
        ((Nil) (translate-body body))
        ((Cons first rest)
         (let ((pair (binding first)))
           (form "let" (list (ListSyntax (list (cell (Pair-first pair) (translate (Pair-second pair))))) (translate-let* rest body)))))))

    (: translate-letrec (-> (List Datum) (List Datum) Syntax))
    (define (translate-letrec bindings body)
      (let ((pairs (map binding bindings)))
        (form "let" (Cons (ListSyntax (empty-cells (map Pair-first pairs)))
                          (append (map (lambda (pair) (form "ref-set!" (list (variable (Pair-first pair)) (translate (Pair-second pair))))) pairs)
                                  (list (translate-body body)))))))

    (: binding (-> Datum (Pair String Datum)))
    (define (binding datum)
      (match datum
        ((PairDatum (SymbolDatum name) (PairDatum value (NullDatum))) (Pair name value))
        (_ (panic (string-append "scheme: expected (name value), got " (datum->string datum))))))

    ;; ---- Conditionals ----

    ;; `(let ((name value)) body)`, where `body` uses the variable. `and`,
    ;; `or`, `cond` and `case` hold the value that decides in a name no
    ;; Scheme name can produce.
    (: holding (-> String Syntax (-> Syntax Syntax) Syntax))
    (define (holding name value body)
      (let ((held (SymbolSyntax name)))
        (form "let" (list (ListSyntax (list (ListSyntax (list held value)))) (body held)))))

    (: translate-and (-> (List Datum) Syntax))
    (define (translate-and args)
      (match args
        ((Nil) (form "BooleanDatum" (list (BooleanSyntax #t))))
        ((Cons last (Nil)) (translate last))
        ((Cons first rest) (holding "and.value" (translate first) (lambda (value) (scheme-if value (translate-and rest) value))))))

    (: translate-or (-> (List Datum) Syntax))
    (define (translate-or args)
      (match args
        ((Nil) (form "BooleanDatum" (list (BooleanSyntax #f))))
        ((Cons last (Nil)) (translate last))
        ((Cons first rest) (holding "or.value" (translate first) (lambda (value) (scheme-if value value (translate-or rest)))))))

    (: translate-cond (-> (List Datum) Syntax))
    (define (translate-cond clauses)
      (match clauses
        ((Nil) unspecified)
        ((Cons clause rest) (translate-clause (items clause) (translate-cond rest)))))

    ;; One clause of a `cond`, given what the clauses after it do.
    (: translate-clause (-> (List Datum) Syntax Syntax))
    (define (translate-clause clause otherwise)
      (match clause
        ((Cons (SymbolDatum "else") body) (translate-body body))
        ((Cons test (Nil)) (holding "cond.value" (translate test) (lambda (value) (scheme-if value value otherwise))))
        ((Cons test (Cons (SymbolDatum "=>") (Cons receiver (Nil))))
         (holding "cond.value" (translate test)
                  (lambda (value) (scheme-if value (form "call" (list (translate receiver) (form "list" (list value)))) otherwise))))
        ((Cons test body) (scheme-if (translate test) (translate-body body) otherwise))
        ((Nil) (panic "scheme: empty cond clause"))))

    (: translate-case (-> Datum (List Datum) Syntax))
    (define (translate-case key clauses)
      (holding "case.key" (translate key) (lambda (held) (case-clauses held clauses))))

    (: case-clauses (-> Syntax (List Datum) Syntax))
    (define (case-clauses key clauses)
      (match clauses
        ((Nil) unspecified)
        ((Cons clause rest)
         (match (items clause)
           ((Cons (SymbolDatum "else") body) (translate-body body))
           ((Cons data body) (form "if" (list (form "member-datum?" (list key (quoted data))) (translate-body body) (case-clauses key rest))))
           ((Nil) (panic "scheme: empty case clause"))))))

    ;; ---- Data ----

    ;; A datum as the Lofi expression that builds it.
    (: quoted (-> Datum Syntax))
    (define (quoted datum)
      (match datum
        ((NullDatum) (form "NullDatum" (Nil)))
        ((BooleanDatum value) (form "BooleanDatum" (list (BooleanSyntax value))))
        ((CharDatum char) (form "CharDatum" (list (CharSyntax char))))
        ((StringDatum text) (form "StringDatum" (list (StringSyntax text))))
        ((SymbolDatum name) (form "SymbolDatum" (list (StringSyntax name))))
        ((NumberDatum n) (form "scheme-number" (list (StringSyntax (number->string n)))))
        ((PairDatum head tail) (form "PairDatum" (list (quoted head) (quoted tail))))
        ((VectorDatum elements) (form "VectorDatum" (list (form "list->vector" (list (form "list" (map quoted (vector->list elements))))))))
        ((BytesDatum bytes) (form "BytesDatum" (list (BytesSyntax bytes))))
        ((ProcedureDatum _) (panic "scheme: a procedure cannot be quoted"))))

    ;; ---- Lists of syntax ----

    (: items (-> Datum (List Datum)))
    (define (items datum)
      (match (datum->list datum)
        ((Some elements) elements)
        ((None) (panic (string-append "scheme: expected a list, got " (datum->string datum))))))

    (: first (-> (List Datum) Datum))
    (define (first data)
      (match data
        ((Cons datum _) datum)
        ((Nil) (panic "scheme: a form is missing a part"))))

    (: second (-> (List Datum) Datum))
    (define (second data)
      (first (list-tail data 1)))

    (: symbol-name (-> Datum String))
    (define (symbol-name datum)
      (match datum
        ((SymbolDatum name) name)
        (_ (panic (string-append "scheme: expected a symbol, got " (datum->string datum))))))

    ))
