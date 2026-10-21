;; An interpreter for Scheme data. Each form is analyzed once into Code, a
;; small tree in which every variable is already found, and the Code is then
;; evaluated as often as it is reached:
;;
;;   text ──read──▶ Datum ──analyze──▶ Code ──evaluate──▶ Datum
;;
;; Analysis rewrites the derived forms into six core forms (quote, if,
;; define, set!, lambda and begin) plus calls. A local variable becomes the
;; number of frames out it lives and its slot there; a global variable
;; becomes its cell, so evaluating either never searches by name. The
;; surface is that of (scheme compiler), plus `do`, and top-level
;; definitions persist in their environment between evaluations, as a
;; REPL's do. Procedures and values come from (scheme runtime); its errors,
;; and this interpreter's, panic.
(define-library (scheme eval)
  (export
   Environment
   standard-environment
   environment-define!
   environment-names
   eval-datum
   eval-text)
  (import
   (lofi base)
   (lofi io)
   (lofi datum)
   (lofi read)
   (lofi write)
   (scheme runtime))
  (begin

    ;; ---- Environments ----

    ;; A global variable is a named cell, empty until something defines it.
    ;; Code that names a variable holds its cell, so a definition evaluated
    ;; later reaches every reference analyzed before it.
    (struct Variable
      ((name String)
       (value (Ref (Option Datum)))))

    ;; The global variables, newest first.
    (struct Environment
      ((variables (Ref (List Variable)))))

    ;; The variable of that name, made empty if there is none yet.
    (: global-variable (-> Environment String Variable ! mut))
    (define (global-variable environment name)
      (let ((variables (Environment-variables environment)))
        (match (find (lambda (variable) (string=? (Variable-name variable) name)) (ref-get variables))
          ((Some variable) variable)
          ((None) (let ((variable (Variable name (ref (None)))))
                    (ref-set! variables (Cons variable (ref-get variables)))
                    variable)))))

    (: environment-define! (-> Environment String Datum Unit ! mut))
    (define (environment-define! environment name value)
      (ref-set! (Variable-value (global-variable environment name)) (Some value)))

    ;; The names that have values, oldest first.
    (: environment-names (-> Environment (List String) ! mut))
    (define (environment-names environment)
      (reverse (map Variable-name (filter (lambda (variable) (match (ref-get (Variable-value variable))
                                                               ((Some _) #t)
                                                               ((None) #f)))
                                          (ref-get (Environment-variables environment))))))

    ;; The standard procedures, each in a cell of its own, so a program
    ;; that redefines one changes only its own environment.
    (: standard-environment (-> Environment ! mut))
    (define (standard-environment)
      (let ((environment (Environment (ref (Nil)))))
        (for-each (lambda (entry) (environment-define! environment (Pair-first entry) (ref-get (Pair-second entry))))
                  standard-procedures)
        environment))

    (: standard-procedures (List (Pair String (Ref Datum))))
    (define standard-procedures
      (list (Pair "+" %+) (Pair "-" %-) (Pair "*" %*) (Pair "/" %/) (Pair "=" %=) (Pair "<" %<) (Pair ">" %>) (Pair "<=" %<=)
            (Pair ">=" %>=) (Pair "quotient" %quotient) (Pair "remainder" %remainder) (Pair "modulo" %modulo) (Pair "abs" %abs)
            (Pair "max" %max) (Pair "min" %min) (Pair "number?" %number?) (Pair "integer?" %integer?) (Pair "zero?" %zero?)
            (Pair "positive?" %positive?) (Pair "negative?" %negative?) (Pair "even?" %even?) (Pair "odd?" %odd?)
            (Pair "number->string" %number->string) (Pair "cons" %cons) (Pair "car" %car) (Pair "cdr" %cdr) (Pair "list" %list)
            (Pair "length" %length) (Pair "append" %append) (Pair "reverse" %reverse) (Pair "list-ref" %list-ref)
            (Pair "null?" %null?) (Pair "pair?" %pair?) (Pair "list?" %list?) (Pair "eq?" %eq?) (Pair "eqv?" %eqv?)
            (Pair "equal?" %equal?) (Pair "not" %not) (Pair "boolean?" %boolean?) (Pair "symbol?" %symbol?)
            (Pair "string?" %string?) (Pair "char?" %char?) (Pair "procedure?" %procedure?) (Pair "string-append" %string-append)
            (Pair "string-length" %string-length) (Pair "substring" %substring) (Pair "string=?" %string=?)
            (Pair "symbol->string" %symbol->string) (Pair "string->symbol" %string->symbol) (Pair "display" %display)
            (Pair "write" %write) (Pair "newline" %newline) (Pair "apply" %apply) (Pair "map" %map) (Pair "for-each" %for-each)
            (Pair "vector" %vector) (Pair "vector-ref" %vector-ref) (Pair "vector-length" %vector-length) (Pair "error" %error)))

    ;; ---- Code ----

    ;; Where analysis found a variable: in a local frame, `depth` frames out
    ;; from the innermost, or global.
    (enum Place
      (Local ((depth I64) (slot I64)))
      (Global ((variable Variable))))

    ;; A procedure's frame has `size` slots: `fixed` parameters, then the
    ;; rest list if `rest`, then the variables its body defines.
    (enum Code
      (Constant ((value Datum)))
      (LocalRef ((depth I64) (slot I64)))
      (LocalSet ((depth I64) (slot I64) (value Code)))
      (GlobalRef ((variable Variable)))
      (GlobalSet ((variable Variable) (value Code)))
      (GlobalDefine ((variable Variable) (value Code)))
      (If ((test Code) (consequent Code) (alternative Code)))
      (Lambda ((fixed I64) (rest Bool) (size I64) (body Code)))
      (Sequence ((first Code) (rest Code)))
      (Call ((operator Code) (operands (List Code)))))

    ;; ---- Frames ----

    ;; The slots of one procedure call, numbered as analysis numbered their
    ;; names, and the frame the procedure was made in.
    (struct Frame
      ((slots (Array Datum))
       (parent (Option Frame))))

    (: frame-at (-> Frame I64 Frame))
    (define (frame-at frame depth)
      (if (= depth 0)
          frame
          (match (Frame-parent frame)
            ((Some parent) (frame-at parent (- depth 1)))
            ((None) (panic "internal error: a local outside every frame")))))

    ;; A call's frame: its arguments, then its rest list, then unassigned
    ;; definitions.
    (: call-slots (-> (List Datum) I64 Bool I64 (Array Datum) ! mut))
    (define (call-slots arguments fixed rest size)
      (arity! arguments fixed rest)
      (let ((slots (make-array size unspecified)))
        (fold-left (lambda (index argument) (when (< index fixed) (array-set! slots index argument)) (+ index 1)) 0 arguments)
        (when rest (array-set! slots fixed (rest-arguments arguments fixed)))
        slots))

    ;; ---- Evaluation ----

    ;; Every call and every branch's body is in tail position, so a Scheme
    ;; tail call becomes a Wasm tail call and a loop runs in constant space.
    (: evaluate (-> Code Frame Datum ! console mut))
    (define (evaluate code frame)
      (match code
        ((Constant value) value)
        ((LocalRef depth slot) (array-ref (Frame-slots (frame-at frame depth)) slot))
        ((LocalSet depth slot value) (array-set! (Frame-slots (frame-at frame depth)) slot (evaluate value frame)) unspecified)
        ((GlobalRef variable) (variable-value variable))
        ((GlobalSet variable value) (assign! variable (evaluate value frame)) unspecified)
        ((GlobalDefine variable value) (ref-set! (Variable-value variable) (Some (evaluate value frame))) unspecified)
        ((If test consequent alternative)
         (if (datum-truthy? (evaluate test frame)) (evaluate consequent frame) (evaluate alternative frame)))
        ((Lambda fixed rest size body) (procedure fixed rest size body frame))
        ((Sequence first rest) (evaluate first frame) (evaluate rest frame))
        ((Call operator operands) (call (evaluate operator frame) (map (lambda (operand) (evaluate operand frame)) operands)))))

    ;; A procedure closes over the frame it was made in.
    (: procedure (-> I64 Bool I64 Code Frame Datum))
    (define (procedure fixed rest size body frame)
      (ProcedureDatum (lambda (arguments) (evaluate body (Frame (call-slots arguments fixed rest size) (Some frame))))))

    (: variable-value (-> Variable Datum ! mut))
    (define (variable-value variable)
      (match (ref-get (Variable-value variable))
        ((Some value) value)
        ((None) (panic (string-append "unbound variable: " (Variable-name variable))))))

    ;; `set!` changes a variable that is defined, as it does in R7RS.
    (: assign! (-> Variable Datum Unit ! mut))
    (define (assign! variable value)
      (variable-value variable)
      (ref-set! (Variable-value variable) (Some value)))

    ;; ---- Analysis ----

    ;; What analysis knows around a form: the environment its globals live
    ;; in, and the names of its local frames, innermost first, each in slot
    ;; order. The top level has no frames.
    (struct Scope
      ((environment Environment)
       (frames (List (List String)))))

    (: syntax-error (All (A) (-> String Datum A)))
    (define (syntax-error message form)
      (panic (string-append "bad syntax, " message ": " (datum->string form))))

    (: analyze (-> Datum Scope Code ! mut))
    (define (analyze datum scope)
      (match datum
        ((SymbolDatum name) (match (resolve name scope)
                              ((Local depth slot) (LocalRef depth slot))
                              ((Global variable) (GlobalRef variable))))
        ((PairDatum (SymbolDatum keyword) _)
         (if (member? keyword special-forms) (analyze-special keyword (parts-of datum) datum scope) (analyze-call datum scope)))
        ((PairDatum _ _) (analyze-call datum scope))
        ((NullDatum) (syntax-error "an empty combination" datum))
        (_ (Constant datum))))

    ;; The innermost local of that name, or else the global.
    (: resolve (-> String Scope Place ! mut))
    (define (resolve name scope)
      (let loop ((frames (Scope-frames scope)) (depth 0))
        (match frames
          ((Nil) (Global (global-variable (Scope-environment scope) name)))
          ((Cons names outer) (match (list-index (lambda (local) (string=? local name)) names)
                                ((Some slot) (Local depth slot))
                                ((None) (loop outer (+ depth 1))))))))

    (: special-forms (List String))
    (define special-forms
      (list "quote" "if" "define" "set!" "lambda" "begin" "let" "let*" "letrec" "letrec*" "cond" "case" "and" "or" "when" "unless"
            "do"))

    ;; The items after a form's keyword.
    (: parts-of (-> Datum (List Datum)))
    (define (parts-of form)
      (match (datum->list form)
        ((Some (Cons _ parts)) parts)
        (_ (syntax-error "an improper form" form))))

    (: analyze-special (-> String (List Datum) Datum Scope Code ! mut))
    (define (analyze-special keyword parts form scope)
      (case keyword
        (("quote") (match parts
                     ((Cons datum (Nil)) (Constant datum))
                     (_ (syntax-error "expected (quote datum)" form))))
        (("if") (analyze-if parts form scope))
        (("define") (analyze-define parts form scope))
        (("set!") (analyze-set parts form scope))
        (("lambda") (match parts
                      ((Cons parameters body) (analyze-lambda parameters body scope))
                      ((Nil) (syntax-error "expected (lambda parameters body ...)" form))))
        (("begin") (sequence (map (lambda (part) (analyze part scope)) parts)))
        (else (analyze (expand-derived keyword parts form) scope))))

    (: analyze-call (-> Datum Scope Code ! mut))
    (define (analyze-call form scope)
      (match (datum->list form)
        ((Some (Cons operator operands)) (Call (analyze operator scope) (map (lambda (operand) (analyze operand scope)) operands)))
        (_ (syntax-error "an improper call" form))))

    ;; Several Codes run in order for the value of the last; none gives the
    ;; unspecified value.
    (: sequence (-> (List Code) Code))
    (define (sequence codes)
      (match codes
        ((Nil) (Constant unspecified))
        ((Cons code (Nil)) code)
        ((Cons code rest) (Sequence code (sequence rest)))))

    (: analyze-if (-> (List Datum) Datum Scope Code ! mut))
    (define (analyze-if parts form scope)
      (match parts
        ((Cons test (Cons consequent (Nil))) (If (analyze test scope) (analyze consequent scope) (Constant unspecified)))
        ((Cons test (Cons consequent (Cons alternative (Nil))))
         (If (analyze test scope) (analyze consequent scope) (analyze alternative scope)))
        (_ (syntax-error "expected (if test consequent [alternative])" form))))

    (: analyze-set (-> (List Datum) Datum Scope Code ! mut))
    (define (analyze-set parts form scope)
      (match parts
        ((Cons (SymbolDatum name) (Cons value (Nil)))
         (match (resolve name scope)
           ((Local depth slot) (LocalSet depth slot (analyze value scope)))
           ((Global variable) (GlobalSet variable (analyze value scope)))))
        (_ (syntax-error "expected (set! name value)" form))))

    ;; ---- Definitions and procedures ----

    ;; `(define name value)`, or `(define (name . parameters) body ...)` as
    ;; the name and a lambda form.
    (: definition (-> Datum (Option (Pair String Datum))))
    (define (definition form)
      (match form
        ((PairDatum (SymbolDatum "define") (PairDatum (SymbolDatum name) (PairDatum value (NullDatum)))) (Some (Pair name value)))
        ((PairDatum (SymbolDatum "define") (PairDatum (PairDatum (SymbolDatum name) parameters) body))
         (Some (Pair name (PairDatum (SymbolDatum "lambda") (PairDatum parameters body)))))
        (_ (None))))

    ;; A body finds its definitions before analyzing its forms, so here only
    ;; the top level remains, where a definition is global.
    (: analyze-define (-> (List Datum) Datum Scope Code ! mut))
    (define (analyze-define parts form scope)
      (match (Pair (definition form) (Scope-frames scope))
        ((Pair (Some (Pair name value)) (Nil)) (GlobalDefine (global-variable (Scope-environment scope) name) (analyze value scope)))
        ((Pair (Some _) _) (syntax-error "a definition must begin a body or be at the top level" form))
        ((Pair (None) _) (syntax-error "expected (define name value) or (define (name parameter ...) body ...)" form))))

    (: analyze-lambda (-> Datum (List Datum) Scope Code ! mut))
    (define (analyze-lambda parameters body scope)
      (let* ((fixed (fixed-parameters parameters)) (rest (rest-parameter parameters))
             (names (frame-names (append fixed rest) body)))
        (Lambda (length fixed) (not (null? rest)) (length names)
                (analyze-body body (Scope-frames-set scope (Cons names (Scope-frames scope)))))))

    (: fixed-parameters (-> Datum (List String)))
    (define (fixed-parameters parameters)
      (match parameters
        ((PairDatum (SymbolDatum name) rest) (Cons name (fixed-parameters rest)))
        ((PairDatum other _) (syntax-error "a parameter must be a name" other))
        (_ (Nil))))

    ;; The rest parameter, as a list of no names or one.
    (: rest-parameter (-> Datum (List String)))
    (define (rest-parameter parameters)
      (match parameters
        ((PairDatum _ rest) (rest-parameter rest))
        ((SymbolDatum name) (list name))
        (_ (Nil))))

    ;; The parameters, then each name the body defines that is not one.
    (: frame-names (-> (List String) (List Datum) (List String)))
    (define (frame-names parameters body)
      (fold-left (lambda (names form)
                   (match (definition form)
                     ((Some (Pair name _)) (if (member? name names) names (append names (list name))))
                     ((None) names)))
                 parameters body))

    ;; A body's definitions assign the slots of the innermost frame.
    (: analyze-body (-> (List Datum) Scope Code ! mut))
    (define (analyze-body forms scope)
      (sequence (map (lambda (form)
                       (match (definition form)
                         ((Some (Pair name value)) (match (resolve name scope)
                                                     ((Local depth slot) (LocalSet depth slot (analyze value scope)))
                                                     ((Global _) (panic "internal error: a body definition outside its frame"))))
                         ((None) (analyze form scope))))
                     forms)))

    ;; ---- Derived forms ----

    ;; Each derived form is rewritten into the forms that mean it.
    ;; Temporaries have names no reader produces, and helper procedures are
    ;; spliced in as constants, so a rewrite never depends on the names a
    ;; program binds. The unspecified value is a constant too.
    (: expand-derived (-> String (List Datum) Datum Datum))
    (define (expand-derived keyword parts form)
      (case keyword
        (("let") (expand-let parts form))
        (("let*") (expand-let* parts form))
        (("letrec" "letrec*") (expand-letrec parts form))
        (("cond") (expand-cond parts form))
        (("case") (expand-case parts form))
        (("and") (expand-and parts))
        (("or") (expand-or parts))
        (("when") (match parts
                    ((Cons test body) (build "if" (list test (build "begin" body))))
                    ((Nil) (syntax-error "expected (when test body ...)" form))))
        (("unless") (match parts
                      ((Cons test body) (build "if" (list test unspecified (build "begin" body))))
                      ((Nil) (syntax-error "expected (unless test body ...)" form))))
        (else (expand-do parts form))))

    (: build (-> String (List Datum) Datum))
    (define (build keyword parts)
      (datum-list (Cons (SymbolDatum keyword) parts)))

    ;; A name with a space in it, which no program can write.
    (: hidden (-> String Datum))
    (define (hidden name)
      (SymbolDatum (string-append " " name)))

    ;; The names and values of `((name value) ...)`.
    (: bindings-of (-> Datum Datum (List (Pair Datum Datum))))
    (define (bindings-of bindings form)
      (map (lambda (item)
             (match item
               ((PairDatum (SymbolDatum name) (PairDatum value (NullDatum))) (Pair (SymbolDatum name) value))
               (_ (syntax-error "expected (name value)" form))))
           (datum-items bindings form)))

    ;; `((name value) ...)` again.
    (: bindings-datum (-> (List (Pair Datum Datum)) Datum))
    (define (bindings-datum pairs)
      (datum-list (map (lambda (pair) (datum-list (list (Pair-first pair) (Pair-second pair)))) pairs)))

    ;; `(let ((name value)) body)`, binding one temporary around a form.
    (: let-one (-> Datum Datum Datum Datum))
    (define (let-one name value body)
      (build "let" (list (bindings-datum (list (Pair name value))) body)))

    ;; `((lambda (name ...) body ...) value ...)`.
    (: expand-let (-> (List Datum) Datum Datum))
    (define (expand-let parts form)
      (match parts
        ((Cons (SymbolDatum name) (Cons bindings body)) (named-let (SymbolDatum name) (bindings-of bindings form) body))
        ((Cons bindings body) (let ((pairs (bindings-of bindings form))) (datum-list (Cons (let-lambda pairs body) (map Pair-second pairs)))))
        ((Nil) (syntax-error "expected (let ((name value) ...) body ...)" form))))

    (: let-lambda (-> (List (Pair Datum Datum)) (List Datum) Datum))
    (define (let-lambda pairs body)
      (build "lambda" (Cons (datum-list (map Pair-first pairs)) body)))

    ;; `((letrec ((name (lambda (variable ...) body ...))) name) value ...)`:
    ;; the values are outside the scope of the name.
    (: named-let (-> Datum (List (Pair Datum Datum)) (List Datum) Datum))
    (define (named-let name pairs body)
      (let ((procedure (build "letrec" (list (bindings-datum (list (Pair name (let-lambda pairs body)))) name))))
        (datum-list (Cons procedure (map Pair-second pairs)))))

    (: expand-let* (-> (List Datum) Datum Datum))
    (define (expand-let* parts form)
      (match parts
        ((Cons bindings body)
         (match (bindings-of bindings form)
           ((Nil) (build "let" (Cons (NullDatum) body)))
           ((Cons first rest) (build "let" (list (bindings-datum (list first)) (build "let*" (Cons (bindings-datum rest) body)))))))
        ((Nil) (syntax-error "expected (let* ((name value) ...) body ...)" form))))

    ;; Each name is defined in a new body before the original body runs.
    (: expand-letrec (-> (List Datum) Datum Datum))
    (define (expand-letrec parts form)
      (match parts
        ((Cons bindings body)
         (build "let" (Cons (NullDatum)
                            (append (map (lambda (pair) (build "define" (list (Pair-first pair) (Pair-second pair)))) (bindings-of bindings form))
                                    (list (build "let" (Cons (NullDatum) body)))))))
        ((Nil) (syntax-error "expected (letrec ((name value) ...) body ...)" form))))

    ;; `(test)` gives the test's value, and `(test => receiver)` passes it
    ;; on, so both hold it in a temporary.
    (: expand-cond (-> (List Datum) Datum Datum))
    (define (expand-cond clauses form)
      (match clauses
        ((Nil) unspecified)
        ((Cons clause rest)
         (match (datum->list clause)
           ((Some (Cons (SymbolDatum "else") body)) (build "begin" body))
           ((Some (Cons test (Nil))) (expand-or (list test (build "cond" rest))))
           ((Some (Cons test (Cons (SymbolDatum "=>") (Cons receiver (Nil)))))
            (let-one (hidden "test") test (build "if" (list (hidden "test") (datum-list (list receiver (hidden "test"))) (build "cond" rest)))))
           ((Some (Cons test body)) (build "if" (list test (build "begin" body) (build "cond" rest))))
           (_ (syntax-error "expected (test body ...) as a cond clause" form))))))

    ;; Each clause's data are compared with `eqv?`, as R7RS says, which
    ;; (scheme runtime) makes structural.
    (: expand-case (-> (List Datum) Datum Datum))
    (define (expand-case parts form)
      (match parts
        ((Cons key clauses)
         (let-one (hidden "key") key (case-clauses clauses form)))
        ((Nil) (syntax-error "expected (case key clause ...)" form))))

    (: case-clauses (-> (List Datum) Datum Datum))
    (define (case-clauses clauses form)
      (match clauses
        ((Nil) unspecified)
        ((Cons clause rest)
         (match (datum->list clause)
           ((Some (Cons (SymbolDatum "else") body)) (build "begin" body))
           ((Some (Cons data body))
            (build "if" (list (datum-list (list member-procedure (hidden "key") (build "quote" (list data))))
                              (build "begin" body) (case-clauses rest form))))
           (_ (syntax-error "expected ((datum ...) body ...) as a case clause" form))))))

    (: member-procedure Datum)
    (define member-procedure
      (ProcedureDatum (lambda (arguments)
                        (match arguments
                          ((Cons item (Cons items (Nil))) (BooleanDatum (member-datum? item items)))
                          (_ (panic "internal error: case membership takes two arguments"))))))

    (: expand-and (-> (List Datum) Datum))
    (define (expand-and tests)
      (match tests
        ((Nil) (BooleanDatum #t))
        ((Cons test (Nil)) test)
        ((Cons test rest) (build "if" (list test (expand-and rest) (BooleanDatum #f))))))

    ;; `or` returns the first true value itself.
    (: expand-or (-> (List Datum) Datum))
    (define (expand-or tests)
      (match tests
        ((Nil) (BooleanDatum #f))
        ((Cons test (Nil)) test)
        ((Cons test rest)
         (let-one (hidden "value") test (build "if" (list (hidden "value") (hidden "value") (expand-or rest)))))))

    ;; `(do ((name init step) ...) (test result ...) body ...)` is a named
    ;; let that ends with the results once the test is true, and otherwise
    ;; runs the body and loops with the steps. A binding without a step
    ;; keeps its value.
    (struct Step
      ((name Datum)
       (init Datum)
       (next Datum)))

    (: expand-do (-> (List Datum) Datum Datum))
    (define (expand-do parts form)
      (match parts
        ((Cons bindings (Cons (PairDatum test results) body))
         (let* ((steps (map (lambda (binding) (do-step binding form)) (datum-items bindings form)))
                (again (datum-list (Cons (hidden "loop") (map Step-next steps)))))
           (named-let (hidden "loop") (map (lambda (step) (Pair (Step-name step) (Step-init step))) steps)
                      (list (build "if" (list test (build "begin" (datum-items results form)) (build "begin" (append body (list again)))))))))
        (_ (syntax-error "expected (do ((name init step) ...) (test result ...) body ...)" form))))

    (: do-step (-> Datum Datum Step))
    (define (do-step binding form)
      (match (datum-items binding form)
        ((Cons (SymbolDatum name) (Cons init (Nil))) (Step (SymbolDatum name) init (SymbolDatum name)))
        ((Cons (SymbolDatum name) (Cons init (Cons next (Nil)))) (Step (SymbolDatum name) init next))
        (_ (syntax-error "expected (name init [step])" form))))

    (: datum-items (-> Datum Datum (List Datum)))
    (define (datum-items datum form)
      (match (datum->list datum)
        ((Some items) items)
        ((None) (syntax-error "expected a list" form))))

    ;; ---- Running ----

    ;; Analyzes and evaluates one form at the top level of `environment`.
    (: eval-datum (-> Datum Environment Datum ! console mut))
    (define (eval-datum datum environment)
      (evaluate (analyze datum (Scope environment (Nil))) (Frame (make-array 0 unspecified) (None))))

    ;; Reads every datum in the text and evaluates them in order, returning
    ;; the last value, or the unspecified value if there are none. Text
    ;; that does not read panics before any of it runs.
    (: eval-text (-> String Environment Datum ! console mut))
    (define (eval-text text environment)
      (match (read-datums text)
        ((Ok data) (fold-left (lambda (value datum) (eval-datum datum environment)) unspecified data))
        ((Err message) (panic (string-append "read: " message)))))

    ))
