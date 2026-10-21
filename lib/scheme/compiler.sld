;; Scheme to Lofi: R7RS source text becomes the text of a Lofi library whose
;; top level runs the program. Every value is a Datum and every variable a
;; cell holding one, named with a leading `%` so no Scheme name meets a Lofi
;; one; (scheme runtime) supplies the standard procedures. A recipe runs the
;; translator when a library is built:
;;
;;   (generate-library (legacy hello)
;;                     (import (lofi io) (scheme compiler))
;;                     (scheme->lofi-library "(legacy hello)" (read-file "hello.scm")))
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
   (lofi write))
  (begin

    ;; ---- Programs ----

    (: scheme->lofi-library (-> String String String))
    (define (scheme->lofi-library name source)
      (match (read-datums source)
        ((Ok forms)
         (string-append "(define-library " name "\n (export)\n (import\n  (lofi base)\n  (lofi datum)\n  (scheme runtime))\n (begin\n"
                        (string-concatenate (map (lambda (form) (string-append "  " (translate-top form) "\n")) forms))
                        "  ))\n"))
        ((Err message) (panic (string-append "scheme: " message)))))

    ;; A top-level definition is a cell; any other form runs at startup.
    (: translate-top (-> Datum String))
    (define (translate-top form)
      (match (definition form)
        ((Some (Pair name value)) (string-append "(define " (variable name) " (ref " (translate value) "))"))
        ((None) (translate form))))

    ;; `(define x e)` and `(define (f . params) body ...)` as a name and a value.
    (: definition (-> Datum (Option (Pair String Datum))))
    (define (definition form)
      (match form
        ((PairDatum (SymbolDatum "define") (PairDatum (SymbolDatum name) (PairDatum value (NullDatum))))
         (Some (Pair name value)))
        ((PairDatum (SymbolDatum "define") (PairDatum (PairDatum (SymbolDatum name) params) body))
         (Some (Pair name (PairDatum (SymbolDatum "lambda") (PairDatum params body)))))
        (_ (None))))

    (: variable (-> String String))
    (define (variable name)
      (string-append "%" name))

    ;; ---- Expressions ----

    (: translate (-> Datum String))
    (define (translate datum)
      (match datum
        ((SymbolDatum name) (string-append "(ref-get " (variable name) ")"))
        ((PairDatum (SymbolDatum keyword) rest)
         (if (member? keyword special-forms) (translate-special keyword (items rest)) (translate-call datum)))
        ((PairDatum _ _) (translate-call datum))
        (_ (quoted datum))))

    (: special-forms (List String))
    (define special-forms
      (list "quote" "lambda" "if" "set!" "let" "let*" "letrec" "letrec*" "begin" "cond" "case" "and" "or" "when" "unless"))

    (: translate-call (-> Datum String))
    (define (translate-call datum)
      (match (items datum)
        ((Cons f arguments) (string-append "(call " (translate f) " (list" (translate-each arguments) "))"))
        ((Nil) (panic "scheme: empty application"))))

    (: translate-each (-> (List Datum) String))
    (define (translate-each data)
      (string-concatenate (map (lambda (datum) (string-append " " (translate datum))) data)))

    (: translate-special (-> String (List Datum) String))
    (define (translate-special keyword args)
      (case keyword
        (("quote") (quoted (first args)))
        (("lambda") (translate-lambda (first args) (list-tail args 1)))
        (("if") (translate-if args))
        (("set!") (string-append "(begin (ref-set! " (variable (symbol-name (first args))) " " (translate (second args)) ") unspecified)"))
        (("let") (translate-let args))
        (("let*") (translate-let* (items (first args)) (list-tail args 1)))
        (("letrec" "letrec*") (translate-letrec (items (first args)) (list-tail args 1)))
        (("begin") (if (null? args) "unspecified" (string-append "(begin" (translate-each args) ")")))
        (("cond") (translate-cond args))
        (("case") (translate-case (first args) (list-tail args 1)))
        (("and") (translate-and args))
        (("or") (translate-or args))
        (("when") (string-append "(if (datum-truthy? " (translate (first args)) ") " (translate-body (list-tail args 1)) " unspecified)"))
        (("unless") (string-append "(if (datum-truthy? " (translate (first args)) ") unspecified " (translate-body (list-tail args 1)) ")"))
        (else (panic (string-append "scheme: unsupported form " keyword)))))

    (: translate-if (-> (List Datum) String))
    (define (translate-if args)
      (match args
        ((Cons test (Cons then (Nil))) (string-append "(if (datum-truthy? " (translate test) ") " (translate then) " unspecified)"))
        ((Cons test (Cons then (Cons otherwise (Nil))))
         (string-append "(if (datum-truthy? " (translate test) ") " (translate then) " " (translate otherwise) ")"))
        (_ (panic "scheme: expected (if test then [else])"))))

    ;; ---- Procedures and bodies ----

    ;; The arguments arrive as a list: fixed parameters take its first
    ;; items, and a rest parameter the remainder.
    (: translate-lambda (-> Datum (List Datum) String))
    (define (translate-lambda params body)
      (let* ((fixed (fixed-parameters params)) (count (length fixed)) (rest (rest-parameter params)))
        (string-append
         "(ProcedureDatum (lambda (arguments) (arity! arguments " (i64->string count) (match rest ((Some _) " #t") ((None) " #f"))
         ") (let ("
         (string-concatenate
          (map-indexed (lambda (index name) (string-append "(" (variable name) " (ref (list-ref arguments " (i64->string index) "))) "))
                       fixed))
         (match rest
           ((Some name) (string-append "(" (variable name) " (ref (rest-arguments arguments " (i64->string count) ")))"))
           ((None) ""))
         ") " (translate-body body) ")))")))

    (: fixed-parameters (-> Datum (List String)))
    (define (fixed-parameters params)
      (match params
        ((PairDatum (SymbolDatum name) rest) (Cons name (fixed-parameters rest)))
        (_ (Nil))))

    (: rest-parameter (-> Datum (Option String)))
    (define (rest-parameter params)
      (match params
        ((PairDatum _ rest) (rest-parameter rest))
        ((SymbolDatum name) (Some name))
        (_ (None))))

    ;; Internal definitions become cells that all exist before any is set,
    ;; so they may refer to each other, as with letrec*.
    (: translate-body (-> (List Datum) String))
    (define (translate-body forms)
      (let ((names (concatenate (map (lambda (form) (match (definition form) ((Some (Pair name _)) (list name)) ((None) (Nil)))) forms))))
        (string-append "(let (" (cells names) ")"
                       (string-concatenate
                        (map (lambda (form)
                               (match (definition form)
                                 ((Some (Pair name value)) (string-append " (ref-set! " (variable name) " " (translate value) ")"))
                                 ((None) (string-append " " (translate form)))))
                             forms))
                       ")")))

    (: cells (-> (List String) String))
    (define (cells names)
      (string-join (map (lambda (name) (string-append "(" (variable name) " (ref unspecified))")) names) " "))

    ;; ---- Binding forms ----

    (: translate-let (-> (List Datum) String))
    (define (translate-let args)
      (match args
        ((Cons (SymbolDatum name) (Cons bindings body))
         (let ((pairs (map binding (items bindings))))
           (string-append "(let ((" (variable name) " (ref unspecified))) (ref-set! " (variable name) " "
                          (translate-lambda (datum-list (map (lambda (pair) (SymbolDatum (Pair-first pair))) pairs)) body)
                          ") (call (ref-get " (variable name) ") (list" (translate-each (map Pair-second pairs)) ")))")))
        ((Cons bindings body)
         (string-append "(let ("
                        (string-join (map (lambda (pair) (string-append "(" (variable (Pair-first pair)) " (ref " (translate (Pair-second pair)) "))"))
                                          (map binding (items bindings)))
                                     " ")
                        ") " (translate-body body) ")"))
        (_ (panic "scheme: expected (let ((name value) ...) body ...)"))))

    (: translate-let* (-> (List Datum) (List Datum) String))
    (define (translate-let* bindings body)
      (match bindings
        ((Nil) (translate-body body))
        ((Cons first rest)
         (let ((pair (binding first)))
           (string-append "(let ((" (variable (Pair-first pair)) " (ref " (translate (Pair-second pair)) "))) "
                          (translate-let* rest body) ")")))))

    (: translate-letrec (-> (List Datum) (List Datum) String))
    (define (translate-letrec bindings body)
      (let ((pairs (map binding bindings)))
        (string-append "(let (" (cells (map Pair-first pairs)) ")"
                       (string-concatenate
                        (map (lambda (pair) (string-append " (ref-set! " (variable (Pair-first pair)) " " (translate (Pair-second pair)) ")")) pairs))
                       " " (translate-body body) ")")))

    (: binding (-> Datum (Pair String Datum)))
    (define (binding datum)
      (match datum
        ((PairDatum (SymbolDatum name) (PairDatum value (NullDatum))) (Pair name value))
        (_ (panic (string-append "scheme: expected (name value), got " (datum->string datum))))))

    ;; ---- Conditionals ----

    ;; `and` and `or` return the deciding value, held in a variable no
    ;; Scheme name can produce.
    (: translate-and (-> (List Datum) String))
    (define (translate-and args)
      (match args
        ((Nil) "(BooleanDatum #t)")
        ((Cons last (Nil)) (translate last))
        ((Cons first rest)
         (string-append "(let ((and.value " (translate first) ")) (if (datum-truthy? and.value) " (translate-and rest) " and.value))"))))

    (: translate-or (-> (List Datum) String))
    (define (translate-or args)
      (match args
        ((Nil) "(BooleanDatum #f)")
        ((Cons last (Nil)) (translate last))
        ((Cons first rest)
         (string-append "(let ((or.value " (translate first) ")) (if (datum-truthy? or.value) or.value " (translate-or rest) "))"))))

    (: translate-cond (-> (List Datum) String))
    (define (translate-cond clauses)
      (match clauses
        ((Nil) "unspecified")
        ((Cons clause rest)
         (match (items clause)
           ((Cons (SymbolDatum "else") body) (translate-body body))
           ((Cons test (Nil))
            (string-append "(let ((cond.value " (translate test) ")) (if (datum-truthy? cond.value) cond.value "
                           (translate-cond rest) "))"))
           ((Cons test (Cons (SymbolDatum "=>") (Cons receiver (Nil))))
            (string-append "(let ((cond.value " (translate test) ")) (if (datum-truthy? cond.value) (call " (translate receiver)
                           " (list cond.value)) " (translate-cond rest) "))"))
           ((Cons test body)
            (string-append "(if (datum-truthy? " (translate test) ") " (translate-body body) " " (translate-cond rest) ")"))
           ((Nil) (panic "scheme: empty cond clause"))))))

    (: translate-case (-> Datum (List Datum) String))
    (define (translate-case key clauses)
      (string-append "(let ((case.key " (translate key) ")) " (case-clauses clauses) ")"))

    (: case-clauses (-> (List Datum) String))
    (define (case-clauses clauses)
      (match clauses
        ((Nil) "unspecified")
        ((Cons clause rest)
         (match (items clause)
           ((Cons (SymbolDatum "else") body) (translate-body body))
           ((Cons data body)
            (string-append "(if (member-datum? case.key " (quoted data) ") " (translate-body body) " " (case-clauses rest) ")"))
           ((Nil) (panic "scheme: empty case clause"))))))

    ;; ---- Data ----

    ;; A datum as the Lofi expression that builds it.
    (: quoted (-> Datum String))
    (define (quoted datum)
      (match datum
        ((NullDatum) "(NullDatum)")
        ((BooleanDatum value) (if value "(BooleanDatum #t)" "(BooleanDatum #f)"))
        ((CharDatum char) (string-append "(CharDatum (integer->char " (i64->string (char->integer char)) "))"))
        ((StringDatum text) (string-append "(StringDatum " (lofi-string text) ")"))
        ((SymbolDatum name) (string-append "(SymbolDatum " (lofi-string name) ")"))
        ((NumberDatum n) (string-append "(scheme-number " (lofi-string (number->string n)) ")"))
        ((PairDatum head tail) (string-append "(PairDatum " (quoted head) " " (quoted tail) ")"))
        ((VectorDatum elements) (string-append "(VectorDatum (list->vector (list" (string-concatenate (map (lambda (item) (string-append " " (quoted item))) (vector->list elements))) ")))"))
        ((BytesDatum _) (panic "scheme: bytevector literals are not supported"))
        ((ProcedureDatum _) (panic "scheme: a procedure cannot be quoted"))))

    (: lofi-string (-> String String))
    (define (lofi-string text)
      (string-append "\""
                     (string-concatenate
                      (map (lambda (c)
                             (cond ((= c #\") "\\\"")
                                   ((= c #\\) "\\\\")
                                   ((= c #\newline) "\\n")
                                   (else (make-string 1 c))))
                           (string->list text)))
                     "\""))

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
