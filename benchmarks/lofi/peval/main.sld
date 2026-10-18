;; Canonical bare Lofi. See migration.json for source provenance.

(import
  (lofi base)
  (lofi io)
  (lofi read)
  (rename (lofi datum) (string->symbol typed-string->symbol) (symbol->string typed-symbol->string))
  (only
    (lofi number)
    number-add
    number-subtract
    number-negate
    number-multiply
    number-divide
    number=?
    number<?
    number>?))

(def peval-symbol? (lambda (value.99) (= (datum-kind value.99) (ann 4 I64))))

(def peval-symbol (lambda (text) (datum-symbol (typed-string->symbol text))))

(def peval-symbol-text (lambda (value.98) (typed-symbol->string (datum-symbol-value value.98))))

(def peval-list-ref
  (lambda (values.4 index.1)
    (if (= index.1 (ann 0 I64)) (datum-car values.4) (peval-list-ref (datum-cdr values.4) (- index.1 (ann 1 I64))))))

(def peval-member?
  (lambda (value.96 values.3)
    (if (not (datum-null? values.3))
      ((lambda (value.97) (if value.97 value.97 (peval-member? value.96 (datum-cdr values.3))))
        (datum-eq? value.96 (datum-car values.3)))
      #f)))

(def peval-for-each
  (lambda (procedure.1 values.2)
    (if (datum-null? values.2)
      (unit)
      (begin
        (procedure.1 (datum-car values.2))
        (peval-for-each procedure.1 (datum-cdr values.2))
        (unit)))))

(def peval-list?
  (lambda (value.95)
    (((lambda () (begin (def loop.7 (lambda (slow fast) (if (not (datum-pair? fast)) (datum-null? fast) ((lambda (next) (if (not (datum-pair? next)) (datum-null? next) ((lambda (slow.1 fast.1) (if (not (datum-eq? slow.1 fast.1)) (loop.7 slow.1 fast.1) #f)) (datum-cdr slow) (datum-cdr next)))) (datum-cdr fast))))) loop.7)))
      value.95
      value.95)))

(def peval-integer (lambda (value.94) (datum-number (exact-number value.94))))

(def peval-add
  (lambda (a.8 b.6) (datum-number (number-add (datum-number-value a.8) (datum-number-value b.6)))))

(def peval-subtract
  (lambda (a.7 b.5)
    (datum-number (number-subtract (datum-number-value a.7) (datum-number-value b.5)))))

(def peval-negate
  (lambda (value.93) (datum-number (number-negate (datum-number-value value.93)))))

(def peval-multiply
  (lambda (a.6 b.4)
    (datum-number (number-multiply (datum-number-value a.6) (datum-number-value b.4)))))

(def peval-divide
  (lambda (a.5 b.3)
    (datum-number (number-divide (datum-number-value a.5) (datum-number-value b.3)))))

(def peval-less? (lambda (a.4 b.2) (number<? (datum-number-value a.4) (datum-number-value b.2))))

(def peval-number=?
  (lambda (a.3 b.1) (number=? (datum-number-value a.3) (datum-number-value b.1))))

(def peval-greater? (lambda (a.2 b) (number>? (datum-number-value a.2) (datum-number-value b))))

(def ReferenceCounts (datatype ()
  (reference-counts
    (total I64 reference-total)
    (operator I64 reference-operator)
    (always Bool reference-always))))

(def Primitive (datatype ()
  (primitive (name Datum primitive-name) (reduce (-> Datum Datum) primitive-reduce))))

(def primitive-list
     (syntax-rules ()
       ((_) (empty-list))
       ((_ first rest ...) (cons first (primitive-list rest ...)))))

(def primitive-lookup
  (lambda (name.4 values args.21)
    (if (null? values)
      (datum-boolean #f)
      ((lambda (entry) (if (datum-eq? name.4 (primitive-name entry)) ((primitive-reduce entry) args.21) (primitive-lookup name.4 (cdr values) args.21)))
        (car values)))))

(def datum-caar (lambda (value.92) (datum-car (datum-car value.92))))

(def datum-cadr (lambda (value.91) (datum-car (datum-cdr value.91))))

(def datum-cdar (lambda (value.90) (datum-cdr (datum-car value.90))))

(def datum-cddr (lambda (value.89) (datum-cdr (datum-cdr value.89))))

(def datum-caddr (lambda (value.88) (datum-car (datum-cdr (datum-cdr value.88)))))

(def datum-cadar (lambda (value.87) (datum-car (datum-cdr (datum-car value.87)))))

(def datum-caddar (lambda (value.86) (datum-car (datum-cdr (datum-cdr (datum-car value.86))))))

(def datum-cadddr (lambda (value.85) (datum-car (datum-cdr (datum-cdr (datum-cdr value.85))))))

(def datum-cdddr (lambda (value.84) (datum-cdr (datum-cdr (datum-cdr value.84)))))

(def peval-literal-0 (datum-list))

(def peval-literal-1 (datum-list))

(def peval-literal-2 (peval-symbol "if"))

(def peval-literal-3 (peval-symbol "begin"))

(def peval-literal-4 (peval-symbol "let"))

(def peval-literal-5 (peval-symbol "letrec"))

(def peval-literal-6 (peval-symbol "let"))

(def peval-literal-7 (peval-symbol "lambda"))

(def peval-literal-8 (peval-symbol "lambda"))

(def peval-literal-9 (peval-symbol "quote"))

(def peval-literal-10 (peval-symbol "quote"))

(def peval-literal-11 (peval-symbol "lambda"))

(def peval-literal-12 (datum-list (datum-list)))

(def peval-literal-13 (peval-symbol "?"))

(def peval-literal-14 (datum-list))

(def peval-literal-15 (datum-list))

(def peval-literal-16 (peval-symbol "if"))

(def peval-literal-17 (peval-symbol "begin"))

(def peval-literal-18 (peval-symbol "let"))

(def peval-literal-19 (peval-symbol "letrec"))

(def peval-literal-20 (peval-symbol "lambda"))

(def peval-literal-21 (peval-symbol "lambda"))

(def peval-literal-22 (peval-symbol "if"))

(def peval-literal-23 (datum-list (datum-boolean #f) (datum-list)))

(def peval-literal-24 (datum-list (peval-symbol "quote") (datum-list)))

(def peval-literal-25 (peval-symbol "begin"))

(def peval-literal-26 (peval-symbol "lambda"))

(def peval-literal-27 (peval-symbol "let"))

(def peval-literal-28 (peval-symbol "letrec"))

(def peval-literal-29 (datum-list))

(def peval-literal-30 (peval-symbol "lambda"))

(def peval-literal-31 (peval-symbol "lambda"))

(def peval-literal-32 (peval-symbol "lambda"))

(def peval-literal-33 (peval-symbol "lambda"))

(def peval-literal-34 (peval-symbol "let"))

(def peval-literal-35 (peval-symbol "if"))

(def peval-literal-36 (peval-symbol "begin"))

(def peval-literal-37 (peval-symbol "let"))

(def peval-literal-38 (peval-symbol "letrec"))

(def peval-literal-39 (peval-symbol "lambda"))

(def peval-literal-40 (peval-symbol "lambda"))

(def peval-literal-41 (datum-list))

(def peval-literal-42 (datum-list))

(def peval-literal-43 (peval-symbol "if"))

(def peval-literal-44 (peval-symbol "begin"))

(def peval-literal-45 (peval-symbol "let"))

(def peval-literal-46 (peval-symbol "letrec"))

(def peval-literal-47 (peval-symbol "lambda"))

(def peval-literal-48 (peval-symbol "let"))

(def peval-literal-49 (peval-symbol "letrec"))

(def peval-literal-50 (peval-symbol "lambda"))

(def peval-literal-51 (peval-symbol "let"))

(def peval-literal-52 (peval-symbol "letrec"))

(def peval-literal-53 (peval-symbol "lambda"))

(def peval-literal-54 (datum-list))

(def peval-literal-55 (peval-symbol "car"))

(def peval-literal-56 (peval-symbol "cdr"))

(def peval-literal-57 (peval-symbol "+"))

(def peval-literal-58 (peval-symbol "*"))

(def peval-literal-59 (peval-symbol "-"))

(def peval-literal-60 (peval-symbol "/"))

(def peval-literal-61 (peval-symbol "<"))

(def peval-literal-62 (peval-symbol "="))

(def peval-literal-63 (peval-symbol ">"))

(def peval-literal-64 (peval-symbol "eq?"))

(def peval-literal-65 (peval-symbol "not"))

(def peval-literal-66 (peval-symbol "null?"))

(def peval-literal-67 (peval-symbol "pair?"))

(def peval-literal-68 (peval-symbol "symbol?"))

(def peval-literal-69 (datum-list))

(def peval-literal-70 (peval-symbol "+"))

(def peval-literal-71 (peval-symbol "*"))

(def peval-literal-72 (peval-symbol "+"))

(def peval-literal-73 (peval-symbol "+"))

(def peval-literal-74 (peval-symbol "+"))

(def peval-literal-75 (peval-symbol "*"))

(def peval-literal-76 (peval-symbol "*"))

(def peval-literal-77 (peval-symbol "*"))

(def peval-literal-78 (peval-symbol "cons"))

(def peval-literal-79 (peval-symbol "list"))

(def peval-literal-80 (peval-symbol "list"))

(def peval-literal-81 (peval-symbol "list"))

(def peval-literal-82
  (datum-list
    (peval-symbol "lambda")
    (datum-list (peval-symbol "a") (peval-symbol "b") (peval-symbol "c"))
    (datum-list
      (peval-symbol "if")
      (datum-list (peval-symbol "null?") (peval-symbol "a"))
      (peval-symbol "b")
      (datum-list
        (peval-symbol "+")
        (datum-list (peval-symbol "car") (peval-symbol "a"))
        (peval-symbol "c")))))

(def peval-literal-83
  (datum-list
    (peval-symbol "lambda")
    (datum-list (peval-symbol "x") (peval-symbol "y"))
    (datum-list
      (peval-symbol "let")
      (datum-list
        (datum-list
          (peval-symbol "q")
          (datum-list
            (peval-symbol "lambda")
            (datum-list (peval-symbol "a") (peval-symbol "b"))
            (datum-list
              (peval-symbol "if")
              (datum-list (peval-symbol "<") (peval-symbol "a") (peval-integer (ann 0 I64)))
              (peval-symbol "b")
              (datum-list (peval-symbol "-") (peval-integer (ann 10 I64)) (peval-symbol "b"))))))
      (datum-list
        (peval-symbol "if")
        (datum-list (peval-symbol "<") (peval-symbol "x") (peval-integer (ann 0 I64)))
        (datum-list
          (peval-symbol "q")
          (datum-list (peval-symbol "-") (peval-symbol "y"))
          (datum-list (peval-symbol "-") (peval-symbol "x")))
        (datum-list (peval-symbol "q") (peval-symbol "y") (peval-symbol "x"))))))

(def peval-literal-84
  (datum-list
    (peval-symbol "lambda")
    (datum-list (peval-symbol "l") (peval-symbol "n"))
    (datum-list
      (peval-symbol "letrec")
      (datum-list
        (datum-list
          (peval-symbol "add-list")
          (datum-list
            (peval-symbol "lambda")
            (datum-list (peval-symbol "l") (peval-symbol "n"))
            (datum-list
              (peval-symbol "if")
              (datum-list (peval-symbol "null?") (peval-symbol "l"))
              (datum-list (peval-symbol "quote") (datum-list))
              (datum-list
                (peval-symbol "cons")
                (datum-list
                  (peval-symbol "+")
                  (datum-list (peval-symbol "car") (peval-symbol "l"))
                  (peval-symbol "n"))
                (datum-list
                  (peval-symbol "add-list")
                  (datum-list (peval-symbol "cdr") (peval-symbol "l"))
                  (peval-symbol "n")))))))
      (datum-list (peval-symbol "add-list") (peval-symbol "l") (peval-symbol "n")))))

(def peval-literal-85
  (datum-list
    (peval-symbol "lambda")
    (datum-list (peval-symbol "exp") (peval-symbol "env"))
    (datum-list
      (peval-symbol "letrec")
      (datum-list
        (datum-list
          (peval-symbol "eval")
          (datum-list
            (peval-symbol "lambda")
            (datum-list (peval-symbol "exp") (peval-symbol "env"))
            (datum-list
              (peval-symbol "letrec")
              (datum-list
                (datum-list
                  (peval-symbol "eval-list")
                  (datum-list
                    (peval-symbol "lambda")
                    (datum-list (peval-symbol "l") (peval-symbol "env"))
                    (datum-list
                      (peval-symbol "if")
                      (datum-list (peval-symbol "null?") (peval-symbol "l"))
                      (datum-list (peval-symbol "quote") (datum-list))
                      (datum-list
                        (peval-symbol "cons")
                        (datum-list
                          (peval-symbol "eval")
                          (datum-list (peval-symbol "car") (peval-symbol "l"))
                          (peval-symbol "env"))
                        (datum-list
                          (peval-symbol "eval-list")
                          (datum-list (peval-symbol "cdr") (peval-symbol "l"))
                          (peval-symbol "env")))))))
              (datum-list
                (peval-symbol "if")
                (datum-list (peval-symbol "symbol?") (peval-symbol "exp"))
                (datum-list (peval-symbol "lookup") (peval-symbol "exp") (peval-symbol "env"))
                (datum-list
                  (peval-symbol "if")
                  (datum-list
                    (peval-symbol "not")
                    (datum-list (peval-symbol "pair?") (peval-symbol "exp")))
                  (peval-symbol "exp")
                  (datum-list
                    (peval-symbol "if")
                    (datum-list
                      (peval-symbol "eq?")
                      (datum-list (peval-symbol "car") (peval-symbol "exp"))
                      (datum-list (peval-symbol "quote") (peval-symbol "quote")))
                    (datum-list
                      (peval-symbol "car")
                      (datum-list (peval-symbol "cdr") (peval-symbol "exp")))
                    (datum-list
                      (peval-symbol "apply")
                      (datum-list
                        (peval-symbol "eval")
                        (datum-list (peval-symbol "car") (peval-symbol "exp"))
                        (peval-symbol "env"))
                      (datum-list
                        (peval-symbol "eval-list")
                        (datum-list (peval-symbol "cdr") (peval-symbol "exp"))
                        (peval-symbol "env"))))))))))
      (datum-list (peval-symbol "eval") (peval-symbol "exp") (peval-symbol "env")))))

(def peval-literal-86
  (datum-list
    (peval-symbol "lambda")
    (datum-list (peval-symbol "a") (peval-symbol "b"))
    (datum-list
      (peval-symbol "letrec")
      (datum-list
        (datum-list
          (peval-symbol "funct")
          (datum-list
            (peval-symbol "lambda")
            (datum-list (peval-symbol "x"))
            (datum-list
              (peval-symbol "+")
              (peval-symbol "x")
              (peval-symbol "b")
              (datum-list
                (peval-symbol "if")
                (datum-list (peval-symbol "<") (peval-symbol "x") (peval-integer (ann 1 I64)))
                (peval-integer (ann 0 I64))
                (datum-list
                  (peval-symbol "funct")
                  (datum-list (peval-symbol "-") (peval-symbol "x") (peval-integer (ann 1 I64)))))))))
      (datum-list (peval-symbol "funct") (peval-symbol "a")))))

(def peval-literal-87
  (datum-list
    (peval-symbol "lambda")
    (datum-list)
    (datum-list
      (peval-symbol "letrec")
      (datum-list
        (datum-list
          (peval-symbol "fib")
          (datum-list
            (peval-symbol "lambda")
            (datum-list (peval-symbol "x"))
            (datum-list
              (peval-symbol "if")
              (datum-list (peval-symbol "<") (peval-symbol "x") (peval-integer (ann 2 I64)))
              (peval-symbol "x")
              (datum-list
                (peval-symbol "+")
                (datum-list
                  (peval-symbol "fib")
                  (datum-list (peval-symbol "-") (peval-symbol "x") (peval-integer (ann 1 I64))))
                (datum-list
                  (peval-symbol "fib")
                  (datum-list (peval-symbol "-") (peval-symbol "x") (peval-integer (ann 2 I64)))))))))
      (datum-list (peval-symbol "fib") (peval-integer (ann 10 I64))))))

(def peval-literal-88
  (datum-list
    (peval-symbol "lambda")
    (datum-list (peval-symbol "input"))
    (datum-list
      (peval-symbol "letrec")
      (datum-list
        (datum-list
          (peval-symbol "copy")
          (datum-list
            (peval-symbol "lambda")
            (datum-list (peval-symbol "in"))
            (datum-list
              (peval-symbol "if")
              (datum-list (peval-symbol "pair?") (peval-symbol "in"))
              (datum-list
                (peval-symbol "cons")
                (datum-list
                  (peval-symbol "copy")
                  (datum-list (peval-symbol "car") (peval-symbol "in")))
                (datum-list
                  (peval-symbol "copy")
                  (datum-list (peval-symbol "cdr") (peval-symbol "in"))))
              (peval-symbol "in")))))
      (datum-list (peval-symbol "copy") (peval-symbol "input")))))

(def peval-literal-89
  (datum-list
    (peval-symbol "lambda")
    (datum-list (peval-symbol "input"))
    (datum-list
      (peval-symbol "letrec")
      (datum-list
        (datum-list
          (peval-symbol "reverse")
          (datum-list
            (peval-symbol "lambda")
            (datum-list (peval-symbol "in") (peval-symbol "result"))
            (datum-list
              (peval-symbol "if")
              (datum-list (peval-symbol "pair?") (peval-symbol "in"))
              (datum-list
                (peval-symbol "reverse")
                (datum-list (peval-symbol "cdr") (peval-symbol "in"))
                (datum-list
                  (peval-symbol "cons")
                  (datum-list (peval-symbol "car") (peval-symbol "in"))
                  (peval-symbol "result")))
              (peval-symbol "result")))))
      (datum-list
        (peval-symbol "reverse")
        (peval-symbol "input")
        (datum-list (peval-symbol "quote") (datum-list))))))

(def peval-literal-90 (datum-list (peval-integer (ann 10 I64)) (peval-integer (ann 11 I64))))

(def peval-literal-91 (peval-integer (ann 1 I64)))

(def peval-literal-92 (peval-integer (ann 1 I64)))

(def peval-literal-93 (peval-integer (ann 1 I64)))

(def peval-literal-94 (datum-list (peval-integer (ann 1 I64)) (peval-integer (ann 2 I64)) (peval-integer (ann 3 I64))))

(def peval-literal-95 (peval-symbol "x"))

(def peval-literal-96
  (datum-list (peval-symbol "f") (peval-integer (ann 1 I64)) (peval-integer (ann 2 I64)) (peval-integer (ann 3 I64))))

(def peval-literal-97 (peval-integer (ann 5 I64)))

(def peval-literal-98 (datum-list))

(def peval-literal-99
  (datum-list
    (peval-symbol "a")
    (peval-symbol "b")
    (peval-symbol "c")
    (peval-symbol "d")
    (peval-symbol "e")
    (peval-symbol "f")
    (peval-symbol "g")
    (peval-symbol "h")
    (peval-symbol "i")
    (peval-symbol "j")
    (peval-symbol "k")
    (peval-symbol "l")
    (peval-symbol "m")
    (peval-symbol "n")
    (peval-symbol "o")
    (peval-symbol "p")
    (peval-symbol "q")
    (peval-symbol "r")
    (peval-symbol "s")
    (peval-symbol "t")
    (peval-symbol "u")
    (peval-symbol "v")
    (peval-symbol "w")
    (peval-symbol "x")
    (peval-symbol "y")
    (peval-symbol "z")))

(def xevery? (-> (-> Datum Bool) Datum Bool)
  (lambda (pred?.1 l.7)
    (((lambda () (begin (def loop.6 (lambda (l.8) ((lambda (value.83) (if value.83 value.83 (if (pred?.1 (datum-car l.8)) (loop.6 (datum-cdr l.8)) #f))) (datum-null? l.8)))) loop.6)))
      l.7)))

(def some? (-> (-> Datum Bool) Datum Bool)
  (lambda (pred? l.5)
    (((lambda () (begin (def loop.5 (lambda (l.6) (if (datum-null? l.6) #f ((lambda (value.82) (if value.82 value.82 (loop.5 (datum-cdr l.6)))) (pred? (datum-car l.6)))))) loop.5)))
      l.5)))

(def map2 (-> (-> Datum Datum Datum) Datum Datum Datum)
  (lambda (f l1 l2)
    (((lambda () (begin (def loop.4 (lambda (l1.1 l2.1) (if (datum-pair? l1.1) ((lambda (head.24) ((lambda (tail.24) ((lambda () (datum-cons head.24 tail.24)))) (loop.4 (datum-cdr l1.1) (datum-cdr l2.1)))) (f (datum-car l1.1) (datum-car l2.1))) peval-literal-0))) loop.4)))
      l1
      l2)))

(def get-last-pair (-> Datum Datum)
  (lambda (l.3)
    (((lambda () (begin (def loop.3 (lambda (l.4) ((lambda (x.19) (if (datum-pair? x.19) (loop.3 x.19) l.4)) (datum-cdr l.4)))) loop.3)))
      l.3)))

(def partial-evaluate (-> Datum Datum Datum)
  (lambda (proc.4 args.20) (peval (alphatize proc.4 peval-literal-1) args.20)))

(def alphatize (-> Datum Datum Datum)
  (lambda (exp.7 env.5)
    (begin
      (def alpha
        (lambda (exp.8)
          (if (const-expr? exp.8)
            (quot (const-value exp.8))
            (if (peval-symbol? exp.8)
              ((lambda (x.18) (if (datum-truth? x.18) (datum-cdr x.18) exp.8))
                (datum-assq exp.8 env.5))
              (if ((lambda (value.81) (if value.81 value.81 (datum-eq? (datum-car exp.8) peval-literal-3))) (datum-eq? (datum-car exp.8) peval-literal-2))
                ((lambda (head.23) ((lambda (tail.23) ((lambda () (datum-cons head.23 tail.23)))) (datum-map alpha (datum-cdr exp.8))))
                  (datum-car exp.8))
                (if ((lambda (value.80) (if value.80 value.80 (datum-eq? (datum-car exp.8) peval-literal-5))) (datum-eq? (datum-car exp.8) peval-literal-4))
                  ((lambda (new-env.3) ((lambda (value.77) ((lambda (value.78) ((lambda (value.79) (datum-list value.77 value.78 value.79)) (alphatize (datum-caddr exp.8) new-env.3))) (datum-map (lambda (x.17) ((lambda (value.75) ((lambda (value.76) (datum-list value.75 value.76)) (if (datum-eq? (datum-car exp.8) peval-literal-6) (alpha (datum-cadr x.17)) (alphatize (datum-cadr x.17) new-env.3)))) (datum-cdr (datum-assq (datum-car x.17) new-env.3)))) (datum-cadr exp.8)))) (datum-car exp.8)))
                    (new-variables (datum-map datum-car (datum-cadr exp.8)) env.5))
                  (if (datum-eq? (datum-car exp.8) peval-literal-7)
                    ((lambda (new-env.2) ((lambda (value.72) ((lambda (value.73) ((lambda (value.74) (datum-list value.72 value.73 value.74)) (alphatize (datum-caddr exp.8) new-env.2))) (datum-map (lambda (x.16) (datum-cdr (datum-assq x.16 new-env.2))) (datum-cadr exp.8)))) peval-literal-8))
                      (new-variables (datum-cadr exp.8) env.5))
                    (datum-map alpha exp.8))))))))
      (alpha exp.7))))

(def const-expr? (-> Datum Bool)
  (lambda (expr.1)
    (if (not (peval-symbol? expr.1))
      ((lambda (value.71) (if value.71 value.71 (datum-eq? (datum-car expr.1) peval-literal-9)))
        (not (datum-pair? expr.1)))
      #f)))

(def const-value (-> Datum Datum) (lambda (expr) (if (datum-pair? expr) (datum-cadr expr) expr)))

(def quot (-> Datum Datum)
  (lambda (val.3)
    ((lambda (value.69) ((lambda (value.70) (datum-list value.69 value.70)) val.3))
      peval-literal-10)))

(def new-variables (-> Datum Datum Datum)
  (lambda (parms.1 env.4)
    (datum-append
      (datum-map
        (lambda (x.15)
          ((lambda (head.22) ((lambda (tail.22) ((lambda () (datum-cons head.22 tail.22)))) (new-variable x.15)))
            x.15))
        parms.1)
      env.4)))

(def *current-num* (ref (ann 0 I64)))

(def new-variable (-> Datum Datum)
  (lambda (name.3)
    (begin
      (ref-set! *current-num* (+ (ref-get *current-num*) (ann 1 I64)))
      (peval-symbol
        (string-append (peval-symbol-text name.3) "_" (i64->string (ref-get *current-num*)))))))

(def peval (-> Datum Datum Datum)
  (lambda (proc.3 args.19)
    (simplify!
      ((lambda (parms body) ((lambda (value.66) ((lambda (value.67) ((lambda (value.68) (datum-list value.66 value.67 value.68)) (beta-subst body (map2 (lambda (x.14 y.3) (if (not-constant? y.3) peval-literal-12 ((lambda (head.21) ((lambda (tail.21) ((lambda () (datum-cons head.21 tail.21)))) (quot y.3))) x.14))) parms args.19)))) (remove-constant parms args.19))) peval-literal-11))
        (datum-cadr proc.3)
        (datum-caddr proc.3)))))

(def not-constant ((lambda (value.65) (datum-list value.65)) peval-literal-13))

(def not-constant? (-> Datum Bool) (lambda (x.13) (datum-eq? x.13 not-constant)))

(def remove-constant (-> Datum Datum Datum)
  (lambda (l.2 a.1)
    (if (datum-null? l.2)
      peval-literal-14
      (if (not-constant? (datum-car a.1))
        ((lambda (head.20) ((lambda (tail.20) ((lambda () (datum-cons head.20 tail.20)))) (remove-constant (datum-cdr l.2) (datum-cdr a.1))))
          (datum-car l.2))
        (remove-constant (datum-cdr l.2) (datum-cdr a.1))))))

(def extract-constant (-> Datum Datum Datum)
  (lambda (l.1 a)
    (if (datum-null? l.1)
      peval-literal-15
      (if (not-constant? (datum-car a))
        (extract-constant (datum-cdr l.1) (datum-cdr a))
        ((lambda (head.19) ((lambda (tail.19) ((lambda () (datum-cons head.19 tail.19)))) (extract-constant (datum-cdr l.1) (datum-cdr a))))
          (datum-car l.1))))))

(def beta-subst (-> Datum Datum Datum)
  (lambda (exp.5 env.3)
    (begin
      (def bs
        (lambda (exp.6)
          (if (const-expr? exp.6)
            (quot (const-value exp.6))
            (if (peval-symbol? exp.6)
              ((lambda (x.12) (if (datum-truth? x.12) (datum-cdr x.12) exp.6))
                (datum-assq exp.6 env.3))
              (if ((lambda (value.64) (if value.64 value.64 (datum-eq? (datum-car exp.6) peval-literal-17))) (datum-eq? (datum-car exp.6) peval-literal-16))
                ((lambda (head.18) ((lambda (tail.18) ((lambda () (datum-cons head.18 tail.18)))) (datum-map bs (datum-cdr exp.6))))
                  (datum-car exp.6))
                (if ((lambda (value.63) (if value.63 value.63 (datum-eq? (datum-car exp.6) peval-literal-19))) (datum-eq? (datum-car exp.6) peval-literal-18))
                  ((lambda (value.60) ((lambda (value.61) ((lambda (value.62) (datum-list value.60 value.61 value.62)) (bs (datum-caddr exp.6)))) (datum-map (lambda (x.11) ((lambda (value.58) ((lambda (value.59) (datum-list value.58 value.59)) (bs (datum-cadr x.11)))) (datum-car x.11))) (datum-cadr exp.6))))
                    (datum-car exp.6))
                  (if (datum-eq? (datum-car exp.6) peval-literal-20)
                    ((lambda (value.55) ((lambda (value.56) ((lambda (value.57) (datum-list value.55 value.56 value.57)) (bs (datum-caddr exp.6)))) (datum-cadr exp.6)))
                      peval-literal-21)
                    (datum-map bs exp.6))))))))
      (bs exp.5))))

(def simplify! (-> Datum Datum)
  (lambda (exp.2)
    (begin
      (def simp!
        (lambda (where.2 env.2)
          (begin
            (def s!
              (lambda (where.3)
                ((lambda (exp.4) (if (const-expr? exp.4) (unit) (if (peval-symbol? exp.4) (unit) (if (datum-eq? (datum-car exp.4) peval-literal-22) (begin (s! (datum-cdr exp.4)) (if (const-expr? (datum-cadr exp.4)) (begin (datum-set-car! where.3 (if (peval-member? (const-value (datum-cadr exp.4)) peval-literal-23) (if (= (datum-length exp.4) (ann 3 I64)) peval-literal-24 (datum-cadddr exp.4)) (datum-caddr exp.4))) (s! where.3)) (for-each! s! (datum-cddr exp.4)))) (if (datum-eq? (datum-car exp.4) peval-literal-25) (begin (for-each! s! (datum-cdr exp.4)) (((lambda () (begin (def loop.2 (lambda (exps.1) (if (not (datum-null? (datum-cddr exps.1))) ((lambda (x.10) (loop.2 (if ((lambda (value.54) (if value.54 value.54 ((lambda (value.53) (if value.53 value.53 (if (datum-pair? x.10) (datum-eq? (datum-car x.10) peval-literal-26) #f))) (peval-symbol? x.10)))) (const-expr? x.10)) (begin (datum-set-cdr! exps.1 (datum-cddr exps.1)) exps.1) (datum-cdr exps.1)))) (datum-cadr exps.1)) (unit)))) loop.2))) exp.4) (if (datum-null? (datum-cddr exp.4)) (datum-set-car! where.3 (datum-cadr exp.4)) (unit))) (if ((lambda (value.52) (if value.52 value.52 (datum-eq? (datum-car exp.4) peval-literal-28))) (datum-eq? (datum-car exp.4) peval-literal-27)) ((lambda (new-env.1) (begin (def keep (lambda (i) (if (>= i (datum-length (datum-cadar where.3))) peval-literal-29 ((lambda (var.4) ((lambda (val.2) ((lambda (refs) ((lambda (self-refs) ((lambda (total-refs) ((lambda (oper-refs) ((lambda () (if (= total-refs (ann 0 I64)) (keep (+ i (ann 1 I64))) (if ((lambda (value.51) (if value.51 value.51 ((lambda (value.50) (if value.50 value.50 ((lambda (value.49) (if value.49 value.49 (if (reference-always refs) (= total-refs (ann 1 I64)) #f))) (if (datum-pair? val.2) (if (datum-eq? (datum-car val.2) peval-literal-30) (if (= total-refs (ann 1 I64)) (if (= oper-refs (ann 1 I64)) (= (reference-total self-refs) (ann 0 I64)) #f) #f) #f) #f)))) (peval-symbol? val.2)))) (const-expr? val.2)) (begin (datum-set-car! where.3 (beta-subst (datum-car where.3) ((lambda (value.48) (datum-list value.48)) ((lambda (head.17) ((lambda (tail.17) ((lambda () (datum-cons head.17 tail.17)))) val.2)) var.4)))) (keep (+ i (ann 1 I64)))) ((lambda (head.16) ((lambda (tail.16) ((lambda () (datum-cons head.16 tail.16)))) (keep (+ i (ann 1 I64))))) var.4)))))) (- (reference-operator refs) (reference-operator self-refs)))) (- (reference-total refs) (reference-total self-refs)))) (ref-count val.2 var.4))) (ref-count (datum-car where.3) var.4))) (datum-cadr (datum-assq var.4 (datum-cadar where.3))))) (datum-car (peval-list-ref (datum-cadar where.3) i)))))) (simp! (datum-cddr exp.4) new-env.1) (for-each! (lambda (x.9) (simp! (datum-cdar x.9) new-env.1)) (datum-cadr exp.4)) ((lambda (to-keep) (if (< (datum-length to-keep) (datum-length (datum-cadar where.3))) (begin (if (datum-null? to-keep) (datum-set-car! where.3 (datum-caddar where.3)) (datum-set-car! (datum-cdar where.3) (datum-map (lambda (v) (datum-assq v (datum-cadar where.3))) to-keep))) (s! where.3)) (if (datum-null? to-keep) (datum-set-car! where.3 (datum-caddar where.3)) (unit)))) (keep (ann 0 I64))))) ((lambda (head.15) ((lambda (tail.15) ((lambda () (datum-cons head.15 tail.15)))) env.2)) exp.4)) (if (datum-eq? (datum-car exp.4) peval-literal-31) (simp! (datum-cddr exp.4) ((lambda (head.14) ((lambda (tail.14) ((lambda () (datum-cons head.14 tail.14)))) env.2)) exp.4)) (begin (for-each! s! exp.4) (if (peval-symbol? (datum-car exp.4)) ((lambda (frame.3) (if (datum-truth? frame.3) ((lambda (proc.2) (if (if (datum-pair? proc.2) (if (datum-eq? (datum-car proc.2) peval-literal-32) (some? const-expr? (datum-cdr exp.4)) #f) #f) ((lambda (args.18) ((lambda (new-proc) ((lambda (new-args) ((lambda () (datum-set-car! where.3 ((lambda (head.13) ((lambda (tail.13) ((lambda () (datum-cons head.13 tail.13)))) new-args)) (add-binding new-proc frame.3 (datum-car exp.4))))))) (remove-constant (datum-cdr exp.4) args.18))) (peval proc.2 args.18))) (arg-pattern (datum-cdr exp.4))) (unit))) (bound-expr (datum-car exp.4) frame.3)) (datum-set-car! where.3 (constant-fold-global (datum-car exp.4) (datum-cdr exp.4))))) (binding-frame (datum-car exp.4) env.2)) (if (not (datum-pair? (datum-car exp.4))) (unit) (if (datum-eq? (datum-caar exp.4) peval-literal-33) (begin (datum-set-car! where.3 ((lambda (value.45) ((lambda (value.46) ((lambda (value.47) (datum-list value.45 value.46 value.47)) (datum-caddar exp.4))) (map2 (lambda (x.8 y.2) ((lambda (value.43) ((lambda (value.44) (datum-list value.43 value.44)) y.2)) x.8)) (datum-cadar exp.4) (datum-cdr exp.4)))) peval-literal-34)) (s! where.3)) (unit))))))))))))
                  (datum-car where.3))))
            (s! where.2))))
      (def remove-empty-calls!
        (lambda (where env.1)
          (begin
            (def rec!
              (lambda (where.1)
                ((lambda (exp.3) (if (const-expr? exp.3) (unit) (if (peval-symbol? exp.3) (unit) (if (datum-eq? (datum-car exp.3) peval-literal-35) (begin (rec! (datum-cdr exp.3)) (rec! (datum-cddr exp.3)) (rec! (datum-cdddr exp.3))) (if (datum-eq? (datum-car exp.3) peval-literal-36) (for-each! rec! (datum-cdr exp.3)) (if ((lambda (value.42) (if value.42 value.42 (datum-eq? (datum-car exp.3) peval-literal-38))) (datum-eq? (datum-car exp.3) peval-literal-37)) ((lambda (new-env) (begin (remove-empty-calls! (datum-cddr exp.3) new-env) (for-each! (lambda (x.7) (remove-empty-calls! (datum-cdar x.7) new-env)) (datum-cadr exp.3)))) ((lambda (head.12) ((lambda (tail.12) ((lambda () (datum-cons head.12 tail.12)))) env.1)) exp.3)) (if (datum-eq? (datum-car exp.3) peval-literal-39) (rec! (datum-cddr exp.3)) (begin (for-each! rec! (datum-cdr exp.3)) (if (if (datum-null? (datum-cdr exp.3)) (peval-symbol? (datum-car exp.3)) #f) ((lambda (frame.2) (if (datum-truth? frame.2) ((lambda (proc.1) (if (if (datum-pair? proc.1) (datum-eq? (datum-car proc.1) peval-literal-40) #f) (begin (ref-set! changed? #t) (datum-set-car! where.1 (datum-caddr proc.1))) (unit))) (bound-expr (datum-car exp.3) frame.2)) (unit))) (binding-frame (datum-car exp.3) env.1)) (unit))))))))))
                  (datum-car where.1))))
            (rec! where))))
      (def changed? (ref #f))
      ((lambda (x.6) (((lambda () (begin (def loop.1 (lambda () (begin (ref-set! changed? #f) (simp! x.6 peval-literal-41) (remove-empty-calls! x.6 peval-literal-42) (if (ref-get changed?) (loop.1) (datum-car x.6))))) loop.1)))))
        ((lambda (value.41) (datum-list value.41)) exp.2)))))

(def ref-count (-> Datum Datum ReferenceCounts)
  (lambda (exp var.3)
    ((lambda (total oper always-evaled) (begin (def rc (lambda (exp.1 ae) (if (const-expr? exp.1) (unit) (if (peval-symbol? exp.1) (if (datum-eq? exp.1 var.3) (begin (ref-set! total (+ (ref-get total) (ann 1 I64))) (ref-set! always-evaled (if ae (ref-get always-evaled) #f))) (unit)) (if (datum-eq? (datum-car exp.1) peval-literal-43) (begin (rc (datum-cadr exp.1) ae) (peval-for-each (lambda (x.5) (rc x.5 #f)) (datum-cddr exp.1))) (if (datum-eq? (datum-car exp.1) peval-literal-44) (peval-for-each (lambda (x.4) (rc x.4 ae)) (datum-cdr exp.1)) (if ((lambda (value.40) (if value.40 value.40 (datum-eq? (datum-car exp.1) peval-literal-46))) (datum-eq? (datum-car exp.1) peval-literal-45)) (begin (peval-for-each (lambda (x.3) (rc (datum-cadr x.3) ae)) (datum-cadr exp.1)) (rc (datum-caddr exp.1) ae)) (if (datum-eq? (datum-car exp.1) peval-literal-47) (rc (datum-caddr exp.1) #f) (begin (peval-for-each (lambda (x.2) (rc x.2 ae)) exp.1) (if (peval-symbol? (datum-car exp.1)) (if (datum-eq? (datum-car exp.1) var.3) (ref-set! oper (+ (ref-get oper) (ann 1 I64))) (unit)) (unit))))))))))) (rc exp #t) (reference-counts (ref-get total) (ref-get oper) (ref-get always-evaled))))
      (ref (ann 0 I64))
      (ref (ann 0 I64))
      (ref #t))))

(def binding-frame (-> Datum Datum Datum)
  (lambda (var.2 env)
    (if (datum-null? env)
      (datum-boolean #f)
      (if ((lambda (value.39) (if value.39 value.39 (datum-eq? (datum-caar env) peval-literal-49))) (datum-eq? (datum-caar env) peval-literal-48))
        (if (datum-truth? (datum-assq var.2 (datum-cadar env)))
          (datum-car env)
          (binding-frame var.2 (datum-cdr env)))
        (if (datum-eq? (datum-caar env) peval-literal-50)
          (if (peval-member? var.2 (datum-cadar env))
            (datum-car env)
            (binding-frame var.2 (datum-cdr env)))
          (datum-fail "ill-formed environment"))))))

(def bound-expr (-> Datum Datum Datum)
  (lambda (var.1 frame.1)
    (if ((lambda (value.38) (if value.38 value.38 (datum-eq? (datum-car frame.1) peval-literal-52))) (datum-eq? (datum-car frame.1) peval-literal-51))
      (datum-cadr (datum-assq var.1 (datum-cadr frame.1)))
      (if (datum-eq? (datum-car frame.1) peval-literal-53)
        not-constant
        (datum-fail "ill-formed frame")))))

(def add-binding (-> Datum Datum Datum Datum)
  (lambda (val frame name.2)
    (begin
      (def find-val
        (lambda (val.1 bindings)
          (if (datum-null? bindings)
            (datum-boolean #f)
            (if (datum=? val.1 (datum-cadar bindings))
              (datum-caar bindings)
              (find-val val.1 (datum-cdr bindings))))))
      ((lambda (value.37) (if (datum-truth? value.37) value.37 ((lambda (var) (begin (datum-set-cdr! (get-last-pair (datum-cadr frame)) ((lambda (value.36) (datum-list value.36)) ((lambda (value.34) ((lambda (value.35) (datum-list value.34 value.35)) val)) var))) var)) (new-variable name.2))))
        (find-val val (datum-cadr frame))))))

(def for-each! (-> (-> Datum Unit) Datum Unit)
  (lambda (proc! l)
    (if (not (datum-null? l)) (begin (proc! l) (for-each! proc! (datum-cdr l))) (unit))))

(def arg-pattern (-> Datum Datum)
  (lambda (exps)
    (if (datum-null? exps)
      peval-literal-54
      ((lambda (head.11) ((lambda (tail.11) ((lambda () (datum-cons head.11 tail.11)))) (arg-pattern (datum-cdr exps))))
        (if (const-expr? (datum-car exps)) (const-value (datum-car exps)) not-constant)))))

(def *primitives*
  (primitive-list
    (primitive
      peval-literal-55
      (lambda (args.4)
        (if (= (datum-length args.4) (ann 1 I64))
          (if (datum-pair? (datum-car args.4))
            (quot (datum-car (datum-car args.4)))
            (datum-boolean #f))
          (datum-boolean #f))))
    (primitive
      peval-literal-56
      (lambda (args.5)
        (if (= (datum-length args.5) (ann 1 I64))
          (if (datum-pair? (datum-car args.5))
            (quot (datum-cdr (datum-car args.5)))
            (datum-boolean #f))
          (datum-boolean #f))))
    (primitive
      peval-literal-57
      (lambda (args.6)
        (if (xevery? datum-number? args.6) (quot (sum args.6 (peval-integer (ann 0 I64)))) (datum-boolean #f))))
    (primitive
      peval-literal-58
      (lambda (args.7)
        (if (xevery? datum-number? args.7)
          (quot (product args.7 (peval-integer (ann 1 I64))))
          (datum-boolean #f))))
    (primitive
      peval-literal-59
      (lambda (args.8)
        (if (> (datum-length args.8) (ann 0 I64))
          (if (xevery? datum-number? args.8)
            (quot
              (if (datum-null? (datum-cdr args.8))
                (peval-negate (datum-car args.8))
                (peval-subtract (datum-car args.8) (sum (datum-cdr args.8) (peval-integer (ann 0 I64))))))
            (datum-boolean #f))
          (datum-boolean #f))))
    (primitive
      peval-literal-60
      (lambda (args.9)
        (if (> (datum-length args.9) (ann 1 I64))
          (if (xevery? datum-number? args.9)
            (quot
              (if (datum-null? (datum-cdr args.9))
                (peval-divide (peval-integer (ann 1 I64)) (datum-car args.9))
                (peval-divide (datum-car args.9) (product (datum-cdr args.9) (peval-integer (ann 1 I64))))))
            (datum-boolean #f))
          (datum-boolean #f))))
    (primitive
      peval-literal-61
      (lambda (args.10)
        (if (= (datum-length args.10) (ann 2 I64))
          (if (xevery? datum-number? args.10)
            (quot (datum-boolean (peval-less? (datum-car args.10) (datum-cadr args.10))))
            (datum-boolean #f))
          (datum-boolean #f))))
    (primitive
      peval-literal-62
      (lambda (args.11)
        (if (= (datum-length args.11) (ann 2 I64))
          (if (xevery? datum-number? args.11)
            (quot (datum-boolean (peval-number=? (datum-car args.11) (datum-cadr args.11))))
            (datum-boolean #f))
          (datum-boolean #f))))
    (primitive
      peval-literal-63
      (lambda (args.12)
        (if (= (datum-length args.12) (ann 2 I64))
          (if (xevery? datum-number? args.12)
            (quot (datum-boolean (peval-greater? (datum-car args.12) (datum-cadr args.12))))
            (datum-boolean #f))
          (datum-boolean #f))))
    (primitive
      peval-literal-64
      (lambda (args.13)
        (if (= (datum-length args.13) (ann 2 I64))
          (quot (datum-boolean (datum-eq? (datum-car args.13) (datum-cadr args.13))))
          (datum-boolean #f))))
    (primitive
      peval-literal-65
      (lambda (args.14)
        (if (= (datum-length args.14) (ann 1 I64))
          (quot (datum-boolean (not (datum-truth? (datum-car args.14)))))
          (datum-boolean #f))))
    (primitive
      peval-literal-66
      (lambda (args.15)
        (if (= (datum-length args.15) (ann 1 I64))
          (quot (datum-boolean (datum-null? (datum-car args.15))))
          (datum-boolean #f))))
    (primitive
      peval-literal-67
      (lambda (args.16)
        (if (= (datum-length args.16) (ann 1 I64))
          (quot (datum-boolean (datum-pair? (datum-car args.16))))
          (datum-boolean #f))))
    (primitive
      peval-literal-68
      (lambda (args.17)
        (if (= (datum-length args.17) (ann 1 I64))
          (quot (datum-boolean (peval-symbol? (datum-car args.17))))
          (datum-boolean #f))))))

(def sum (-> Datum Datum Datum)
  (lambda (lst.1 n.1)
    (if (datum-null? lst.1) n.1 (sum (datum-cdr lst.1) (peval-add n.1 (datum-car lst.1))))))

(def product (-> Datum Datum Datum)
  (lambda (lst n)
    (if (datum-null? lst) n (product (datum-cdr lst) (peval-multiply n (datum-car lst))))))

(def reduce-global (-> Datum Datum Datum)
  (lambda (name.1 args.3) (primitive-lookup name.1 *primitives* args.3)))

(def constant-fold-global (-> Datum Datum Datum)
  (lambda (name exprs)
    (begin
      (def flatten
        (lambda (args.2 op)
          (if (datum-null? args.2)
            peval-literal-69
            (if (if (datum-pair? (datum-car args.2)) (datum-eq? (datum-caar args.2) op) #f)
              (datum-append (flatten (datum-cdar args.2) op) (flatten (datum-cdr args.2) op))
              ((lambda (head.10) ((lambda (tail.10) ((lambda () (datum-cons head.10 tail.10)))) (flatten (datum-cdr args.2) op)))
                (datum-car args.2))))))
      ((lambda (args.1) ((lambda (value.33) (if (datum-truth? value.33) value.33 ((lambda (pattern) ((lambda (non-const const) (if (datum-eq? name peval-literal-72) ((lambda (x.1) (if (datum-truth? x.1) ((lambda (y.1) ((lambda (head.9) ((lambda (tail.9) ((lambda () (datum-cons head.9 tail.9)))) (if (peval-number=? y.1 (peval-integer (ann 0 I64))) non-const ((lambda (head.8) ((lambda (tail.8) ((lambda () (datum-cons head.8 tail.8)))) non-const)) x.1)))) peval-literal-74)) (const-value x.1)) ((lambda (head.7) ((lambda (tail.7) ((lambda () (datum-cons head.7 tail.7)))) args.1)) name))) (reduce-global peval-literal-73 const)) (if (datum-eq? name peval-literal-75) ((lambda (x) (if (datum-truth? x) ((lambda (y) ((lambda (head.6) ((lambda (tail.6) ((lambda () (datum-cons head.6 tail.6)))) (if (peval-number=? y (peval-integer (ann 1 I64))) non-const ((lambda (head.5) ((lambda (tail.5) ((lambda () (datum-cons head.5 tail.5)))) non-const)) x)))) peval-literal-77)) (const-value x)) ((lambda (head.4) ((lambda (tail.4) ((lambda () (datum-cons head.4 tail.4)))) args.1)) name))) (reduce-global peval-literal-76 const)) (if (datum-eq? name peval-literal-78) (if (if (const-expr? (datum-cadr args.1)) (datum-null? (const-value (datum-cadr args.1))) #f) ((lambda (value.31) ((lambda (value.32) (datum-list value.31 value.32)) (datum-car args.1))) peval-literal-79) (if (if (datum-pair? (datum-cadr args.1)) (datum-eq? (datum-car (datum-cadr args.1)) peval-literal-80) #f) ((lambda (head.3) ((lambda (tail.3) ((lambda () (datum-cons head.3 tail.3)))) ((lambda (head.2) ((lambda (tail.2) ((lambda () (datum-cons head.2 tail.2)))) (datum-cdr (datum-cadr args.1)))) (datum-car args.1)))) peval-literal-81) ((lambda (head.1) ((lambda (tail.1) ((lambda () (datum-cons head.1 tail.1)))) args.1)) name))) ((lambda (head) ((lambda (tail) ((lambda () (datum-cons head tail)))) args.1)) name))))) (remove-constant args.1 pattern) (datum-map const-value (extract-constant args.1 pattern)))) (arg-pattern args.1)))) (if (xevery? const-expr? args.1) (reduce-global name (datum-map const-value args.1)) (datum-boolean #f))))
        (if ((lambda (value.30) (if value.30 value.30 (datum-eq? name peval-literal-71))) (datum-eq? name peval-literal-70))
          (flatten exprs name)
          exprs)))))

(def try-peval (-> Datum Datum Datum) (lambda (proc args) (partial-evaluate proc args)))

(def example1 peval-literal-82)

(def example2 peval-literal-83)

(def example3 peval-literal-84)

(def example4 peval-literal-85)

(def example5 peval-literal-86)

(def example6 peval-literal-87)

(def example7 peval-literal-88)

(def example8 peval-literal-89)

(def test (-> Datum Datum Datum)
  (lambda (input1.1 input2)
    (begin
      (ref-set! *current-num* (ann 0 I64))
      ((lambda (value.20) ((lambda (value.21) ((lambda (value.22) ((lambda (value.23) ((lambda (value.24) ((lambda (value.25) ((lambda (value.26) ((lambda (value.27) ((lambda (value.28) ((lambda (value.29) (datum-list value.20 value.21 value.22 value.23 value.24 value.25 value.26 value.27 value.28 value.29)) (try-peval input1.1 input2))) (try-peval example7 ((lambda (value.19) (datum-list value.19)) peval-literal-99)))) (try-peval example6 peval-literal-98))) (try-peval example5 ((lambda (value.17) ((lambda (value.18) (datum-list value.17 value.18)) not-constant)) peval-literal-97)))) (try-peval example4 ((lambda (value.15) ((lambda (value.16) (datum-list value.15 value.16)) not-constant)) peval-literal-96)))) (try-peval example4 ((lambda (value.13) ((lambda (value.14) (datum-list value.13 value.14)) not-constant)) peval-literal-95)))) (try-peval example3 ((lambda (value.11) ((lambda (value.12) (datum-list value.11 value.12)) not-constant)) peval-literal-94)))) (try-peval example3 ((lambda (value.9) ((lambda (value.10) (datum-list value.9 value.10)) peval-literal-93)) not-constant)))) (try-peval example2 ((lambda (value.7) ((lambda (value.8) (datum-list value.7 value.8)) peval-literal-92)) not-constant))))
        (try-peval
          example1
          ((lambda (value.4) ((lambda (value.5) ((lambda (value.6) (datum-list value.4 value.5 value.6)) peval-literal-91)) not-constant))
            peval-literal-90))))))

(def Specification (datatype ()
  (specification
    (count I64 specification-count)
    (procedure Datum specification-procedure)
    (arguments Datum specification-arguments)
    (expected Datum specification-expected))))

(def read-specification
  (lambda (port)
    ((lambda (count.3) ((lambda (procedure) ((lambda (arguments) ((lambda (expected.1) ((lambda () (specification count.3 procedure arguments expected.1)))) (read-value! (read port)))) (read-value! (read port)))) (read-value! (read port))))
      (exact-count (read-value! (read port))))))

(def exact-count
  (lambda (value.3)
    (match (datum-number-value value.3)
      ((exact-number count.2) count.2)
      ((rational-number value.1) (datum-fail "peval: count must be an exact I64"))
      ((inexact-number value.2) (datum-fail "peval: count must be exact"))
      ((complex-number real imaginary) (datum-fail "peval: count must be exact")))))

(def configured (call-with-input-file "input.txt" read-specification))

(def input0 (specification-procedure configured))

(def input1 (specification-arguments configured))

(def expected (specification-expected configured))

(def configured-count (-> I64) (lambda () (specification-count configured)))

(define-extern barrier "benchmark" "barrier" (-> Bool))

(def hide (lambda (count.1 value) (if (barrier) value (unreachable))))

(def correct-result?
  (lambda (result.1 output)
    (if (peval-list? result.1)
      (if (= (datum-length result.1) (ann 10 I64)) (datum=? (peval-list-ref result.1 (ann 9 I64)) output) #f)
      #f)))

(def bench (-> I64 I64)
  (lambda (count)
    (((lambda () (begin (def loop (lambda (index result) (if (< index count) (loop (+ index (ann 1 I64)) (test (hide count input0) (hide count input1))) (if (correct-result? result expected) (ann 1 I64) (ann 0 I64))))) loop)))
      (ann 0 I64)
      (datum-boolean #f))))

(unit)
