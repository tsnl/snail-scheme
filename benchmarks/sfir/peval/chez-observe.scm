(import (except (chezscheme) string-copy! vector-copy!))
(define-syntax : (syntax-rules () ((_ . signature) (begin))))
(define-syntax ann (syntax-rules () ((_ value type) value)))
(define-syntax define-overload (syntax-rules () ((_ . declaration) (begin))))
(define-syntax define-data
  (lambda (form)
    (syntax-case form ()
      ((context name variant ...)
       (datum->syntax #'context
         (cons 'begin
           (apply append
             (map (lambda (variant)
                    (let ((tag (car variant)) (fields (cdr variant)))
                      (cons `(define (,tag ,@(map car fields)) (vector ',tag ,@(map car fields)))
                        (let loop ((fields fields) (index 1))
                          (if (null? fields) '()
                              (append
                                (if (= (length (car fields)) 3)
                                    `((define (,(caddar fields) value)
                                        (unless (eq? (vector-ref value 0) ',tag)
                                          (error ',tag "wrong typed variant" value))
                                        (vector-ref value ,index))) '())
                                (loop (cdr fields) (+ index 1))))))))
                  (syntax->datum #'(variant ...))))))))))
(define-syntax match
  (lambda (form)
    (syntax-case form ()
      ((context value arm ...)
       (let ((temporary (syntax->datum (car (generate-temporaries #'(value))))))
         (datum->syntax #'context
           `(let ((,temporary ,(syntax->datum #'value)))
              (cond
                ,@(map (lambda (arm)
                         (let ((pattern (car arm)))
                           `((eq? (vector-ref ,temporary 0) ',(car pattern))
                             (let ,(let loop ((names (cdr pattern)) (index 1))
                                     (if (null? names) '()
                                         (cons `(,(car names) (vector-ref ,temporary ,index))
                                           (loop (cdr names) (+ index 1)))))
                               ,@(cdr arm)))))
                       (syntax->datum #'(arm ...)))
                (else (error 'match "invalid typed variant" ,temporary))))))))))
(define (unit) (if #f #f))
(define (unreachable) (error 'reader "unreachable typed branch"))
(define (ref value) (vector value))
(define (ref-get value) (vector-ref value 0))
(define (ref-set! cell value) (vector-set! cell 0 value))
(define ref-eq? eq?)
(define vector-eq? eq?)
(define string-eq? eq?)
(define bytevector-eq? eq?)
(define i32-eq eqv?)
(define i32->i64 values)
(define i64->i32 values)
(define i64->f64 inexact)
(define (f64->i64 value)
  (unless (and (finite? value) (<= -9223372036854775808.0 value) (< value 9223372036854775808.0))
    (error 'f64->i64 "out of range" value))
  (exact (truncate value)))
(define (empty-vector) (vector))
;; The identical Datum body hashes complete wrapping I64 words. Chez's generic
;; integers do not wrap, so these scalar adapters make that boundary explicit.
(define (i64-word value)
  (let ((bits (bitwise-bit-field value 0 64)))
    (if (< bits 9223372036854775808) bits (- bits 18446744073709551616))))
(define (i64-add a b) (i64-word (+ a b)))
(define (i64-mul a b) (i64-word (* a b)))
(define (i64-bitwise-and a b) (bitwise-if a b 0))
(define i64-bitwise-xor bitwise-xor)
(define (i64-shift-right/logical value count)
  (i64-word (bitwise-arithmetic-shift-right (bitwise-bit-field value 0 64)
                                          (bitwise-bit-field count 0 6))))
(define (string-copy! target at source start end)
  (do ((index start (+ index 1))) ((= index end))
    (string-set! target (+ at (- index start)) (string-ref source index))))
(define (vector-copy! target at source start end)
  (let ((count (- end start)))
    (if (and (eq? target source) (> at start))
        (do ((index (- count 1) (- index 1))) ((< index 0))
          (vector-set! target (+ at index) (vector-ref source (+ start index))))
        (do ((index 0 (+ index 1))) ((= index count))
          (vector-set! target (+ at index) (vector-ref source (+ start index)))))))
(define peval-list list)
(define peval-symbol string->symbol)
(define peval-integer values)
(define datum-cons cons)
(define datum-car car)
(define datum-cdr cdr)
(define datum-cadr cadr)
(define datum-caddr caddr)
(define datum-null? null?)
(define datum-eq? eq?)
(define datum=? equal?)
(define datum-set-car! set-car!)
(define datum-set-cdr! set-cdr!)
(define datum-boolean values)
(define reference-total car)
(define reference-operator cadr)
(define reference-always caddr)
(define (datum-null) '())
(define (fresh-name-count) *current-num*)
(define (correct-result? result output)
  (and (list? result) (= (length result) 10) (equal? (list-ref result 9) output)))
(define observer-counts (make-vector 48 0))
(define (emit-i64 value) (display "i:") (display value) (newline))
(define (emit-char value) (display "c:") (display (char->integer value)) (newline))
(define (emit-f64 value)
  (display "f:")
  (if (nan? value) (display "nan")
      (let ((bytes (make-bytevector 8)))
        (bytevector-ieee-double-native-set! bytes 0 value)
        (display (bytevector-u64-native-ref bytes 0))))
  (newline))
(define (observe-string value)
  (emit-i64 (string-length value)) (string-for-each emit-char value))
(define (observe-scalar value)
  (if (exact? value)
      (if (and (integer? value) (<= -9223372036854775808 value 9223372036854775807))
          (begin (emit-i64 0) (emit-i64 value))
          (begin (emit-i64 3) (observe-string (number->string (numerator value)))
                 (observe-string (number->string (denominator value)))))
      (begin (emit-i64 1) (emit-f64 value))))
(define (observe-number value)
  (if (and (not (flonum? value)) (or (cflonum? value) (not (real? value))))
      (begin (emit-i64 2) (observe-scalar (real-part value)) (observe-scalar (imag-part value)))
      (observe-scalar value)))
(define (observe value)
  (cond
   ((null? value) (emit-i64 0))
   ((boolean? value) (emit-i64 1) (emit-i64 (if value 1 0)))
   ((char? value) (emit-i64 2) (emit-char value))
   ((string? value) (emit-i64 3) (observe-string value))
   ((symbol? value) (emit-i64 4) (observe-string (symbol->string value)))
   ((number? value) (emit-i64 5) (observe-number value))
   ((pair? value) (emit-i64 6) (observe (car value)) (observe (cdr value)))
   ((vector? value) (emit-i64 7) (emit-i64 (vector-length value)) (vector-for-each observe value))
   ((bytevector? value) (emit-i64 8) (emit-i64 (bytevector-length value))
    (do ((index 0 (+ index 1))) ((= index (bytevector-length value)))
      (emit-i64 (bytevector-u8-ref value index))))
   (else (error 'observe "unsupported oracle value" value))))
;; Separate observations exercise the original evaluator and mutable cells.
;; This file is never part of a clean benchmark worker.

;; ---- Work observations retain complete results and original operation counts ----

(define observer-case (ref 0))
(define (observer-tick! index)
  (vector-set! observer-counts index (+ (vector-ref observer-counts index) 1)))
(define (observer-reset!)
  (ref-set! observer-case 0)
  (let loop ((index 0))
    (unless (= index (vector-length observer-counts))
      (vector-set! observer-counts index 0) (loop (+ index 1)))))
(define (observer-counts!)
  (emit-i64 (vector-length observer-counts))
  (let loop ((index 0))
    (unless (= index (vector-length observer-counts))
      (emit-i64 (vector-ref observer-counts index)) (loop (+ index 1)))))
(define (observer-name name result)
  (emit-i64 101) (observe name) (observe result) result)
(define (observer-case-start!)
  (emit-i64 102) (emit-i64 (ref-get observer-case))
  (ref-set! observer-case (+ (ref-get observer-case) 1)))
(define (observer-case-result result)
  (emit-i64 103) (observe result) (emit-i64 (fresh-name-count)) (observer-counts!) result)
(: observe-once (-> I64))
(define (observe-once)
  (let loop ((index 0))
    (unless (= index (configured-count))
      (observer-reset!) (emit-i64 100) (emit-i64 index)
      (let ((result (test input0 input1)))
        (emit-i64 104) (observe result) (emit-i64 (fresh-name-count)) (observer-counts!))
      (loop (+ index 1)))) 1)

;; ---- Shared syntax and borrowed list cells remain observable through writes ----

(define (probe-check value)
  (emit-i64 110) (emit-i64 (if value 1 0))
  (unless value (unreachable)))
(define (probe-sentinel)
  (probe-check (not-constant? not-constant))
  (probe-check (not (not-constant? (peval-list (peval-symbol "?"))))))
(define (probe-substitution)
  (let* ((name (peval-symbol "probe-x")) (value (peval-list (peval-symbol "before")))
         (source (peval-list (peval-symbol "list") name name))
         (result (beta-subst source (peval-list (datum-cons name value)))))
    (probe-check (not (datum-eq? source result)))
    (probe-check (datum-eq? (datum-cadr result) value))
    (probe-check (datum-eq? (datum-caddr result) value))
    (datum-set-car! value (peval-symbol "after"))
    (probe-check (datum-eq? (datum-cadr source) name))
    (emit-i64 111) (observe source) (observe result)))
(define (probe-binding)
  (let* ((name (peval-symbol "bound")) (value (quot (peval-integer 2)))
         (bindings (peval-list (peval-list name (quot (peval-integer 1)))))
         (last bindings) (frame (peval-list (peval-symbol "let") bindings name))
         (before (fresh-name-count)) (added (add-binding value frame name)))
    (probe-check (datum-eq? bindings (datum-cadr frame)))
    (probe-check (datum-eq? value (datum-cadr (datum-car (datum-cdr last)))))
    (probe-check (datum-eq? added (add-binding (quot (peval-integer 2)) frame name)))
    (probe-check (= (fresh-name-count) (+ before 1)))))
(define (probe-cell-traversal)
  (let* ((a (peval-symbol "a")) (b (peval-symbol "b"))
         (tail (peval-list b (peval-symbol "c"))) (values (datum-cons a tail)) (seen (ref 0)))
    (for-each! (lambda (cell)
                 (ref-set! seen (+ (ref-get seen) 1))
                 (when (datum-eq? (datum-car cell) b) (datum-set-cdr! cell (datum-null)))) values)
    (probe-check (= (ref-get seen) 2))
    (probe-check (datum-eq? (datum-cdr values) tail))
    (probe-check (datum-null? (datum-cdr tail)))))
(define (probe-begin-mutation)
  (let* ((effect (peval-list (peval-symbol "display") (quot (peval-integer 3))))
         (tail (peval-list effect (quot (peval-integer 4))))
         (source (datum-cons (peval-symbol "begin") (datum-cons (quot (peval-integer 1)) tail)))
         (result (simplify! source)))
    (probe-check (datum-eq? source result))
    (probe-check (datum-eq? (datum-cdr source) tail))
    (probe-check (not (datum-eq? (datum-cadr result) effect)))
    (probe-check (datum=? (datum-cadr result) effect))
    (emit-i64 112) (observe result)))
(define (probe-reference-count)
  (let* ((x (peval-symbol "x"))
         (conditional (peval-list (peval-symbol "if") x (peval-list x x)
                        (peval-list (peval-symbol "lambda") (peval-list (peval-symbol "y")) x)))
         (count (ref-count conditional x)))
    (probe-check (= (reference-total count) 4))
    (probe-check (= (reference-operator count) 1))
    (probe-check (not (reference-always count)))))

;; ---- Primitive guards distinguish failure from a successfully quoted false ----

(define (probe-primitive name arguments)
  (emit-i64 113) (observe (peval-symbol name)) (observe arguments)
  (observe (reduce-global (peval-symbol name) arguments)))
(define (probe-numeric-primitives)
  (probe-primitive "+" (datum-null)) (probe-primitive "*" (datum-null))
  (probe-primitive "-" (peval-list (peval-integer 4)))
  (probe-primitive "-" (peval-list (peval-integer 10) (peval-integer 1) (peval-integer 2)))
  (probe-primitive "/" (peval-list (peval-integer 2)))
  (probe-primitive "/" (peval-list (peval-integer 1) (peval-integer 2)))
  (probe-primitive "<" (peval-list (peval-integer 2) (peval-integer 3)))
  (probe-primitive "=" (peval-list (peval-integer 2) (peval-integer 2)))
  (probe-primitive ">" (peval-list (peval-integer 2) (peval-integer 3)))
  (probe-primitive "+" (peval-list (peval-symbol "not-a-number"))))
(define (probe-data-primitives)
  (let ((a (peval-symbol "a")) (pair (peval-list (peval-symbol "a"))))
    (probe-primitive "car" (peval-list pair)) (probe-primitive "cdr" (peval-list pair))
    (probe-primitive "car" (peval-list a)) (probe-primitive "car" (datum-null))
    (probe-primitive "eq?" (peval-list a a)) (probe-primitive "eq?" (peval-list pair pair))
    (probe-primitive "eq?" (peval-list pair (peval-list a)))
    (probe-primitive "not" (peval-list (datum-boolean #f)))
    (probe-primitive "not" (peval-list (datum-null)))
    (probe-primitive "null?" (peval-list (datum-null)))
    (probe-primitive "pair?" (peval-list pair)) (probe-primitive "symbol?" (peval-list a))
    (probe-primitive "unknown" (peval-list a))))
(define (probe-associative-folding)
  (let* ((x (peval-symbol "x")) (y (peval-symbol "y")) (plus (peval-symbol "+"))
         (times (peval-symbol "*")) (two (quot (peval-integer 2))))
    (emit-i64 114)
    (observe (constant-fold-global plus (peval-list x (peval-list plus two y) (quot (peval-integer 0)))))
    (observe (constant-fold-global times (peval-list x (peval-list times two y) (quot (peval-integer 1)))))
    (observe (constant-fold-global plus (peval-list x (quot (peval-symbol "non-number")))))))

;; ---- The original predicate inspects all shape guards and the entire tenth value ----

(define (probe-result-prefix tail)
  (let loop ((index 9) (result tail))
    (if (= index 0) result (loop (- index 1) (datum-cons (datum-boolean #f) result)))))
(define (probe-predicate)
  (let* ((value (peval-list (peval-symbol "lambda") (datum-null) (quot (peval-integer 7))))
         (result (probe-result-prefix (peval-list value))))
    (probe-check (correct-result? result value))
    (probe-check (not (correct-result? (datum-cdr result) value)))
    (probe-check (not (correct-result? (datum-cons value result) value)))
    (probe-check (not (correct-result? result (quot (peval-integer 7)))))
    (probe-check (not (correct-result? (probe-result-prefix (peval-symbol "tail")) value)))
    (datum-set-cdr! (get-last-pair result) result)
    (probe-check (not (correct-result? result value)))))
(: semantics-probe (-> I64))
(define (semantics-probe)
  (probe-sentinel) (probe-substitution) (probe-binding) (probe-cell-traversal)
  (probe-begin-mutation) (probe-reference-count) (probe-numeric-primitives)
  (probe-data-primitives) (probe-associative-folding) (probe-predicate) 42)
;;; PEVAL -- A simple partial evaluator for Scheme, written by Marc Feeley.



;;------------------------------------------------------------------------------

;; Utilities

(define (xevery?-observed pred? l)
  (let loop ((l l))
    (or (null? l) (and (pred? (car l)) (loop (cdr l))))))

(define (some?-observed pred? l)
  (let loop ((l l))
    (if (null? l) #f (or (pred? (car l)) (loop (cdr l))))))

(define (map2-observed f l1 l2)
  (let loop ((l1 l1) (l2 l2))
    (if (pair? l1)
        (cons (f (car l1) (car l2)) (loop (cdr l1) (cdr l2)))
        '())))

(define (get-last-pair-observed l)
  (let loop ((l l))
    (let ((x (cdr l))) (if (pair? x) (loop x) l))))

;;------------------------------------------------------------------------------
;;
;; The partial evaluator.

(define (partial-evaluate-observed proc args)
  (peval (alphatize proc '()) args))

(define (alphatize-observed exp env);; return a copy of 'exp' where each bound var has
  (define (alpha exp);; been renamed (to prevent aliasing problems)
    (cond ((const-expr? exp)
           (quot (const-value exp)))
          ((symbol? exp)
           (let ((x (assq exp env))) (if x (cdr x) exp)))
          ((or (eq? (car exp) 'if) (eq? (car exp) 'begin))
           (cons (car exp) (map alpha (cdr exp))))
          ((or (eq? (car exp) 'let) (eq? (car exp) 'letrec))
           (let ((new-env (new-variables (map car (cadr exp)) env)))
             (list (car exp)
                   (map (lambda (x)
                          (list (cdr (assq (car x) new-env))
                                (if (eq? (car exp) 'let)
                                    (alpha (cadr x))
                                    (alphatize (cadr x) new-env))))
                        (cadr exp))
                   (alphatize (caddr exp) new-env))))
          ((eq? (car exp) 'lambda)
           (let ((new-env (new-variables (cadr exp) env)))
             (list 'lambda
                   (map (lambda (x) (cdr (assq x new-env))) (cadr exp))
                   (alphatize (caddr exp) new-env))))
          (else
           (map alpha exp))))
  (alpha exp))

(define (const-expr?-observed expr);; is 'expr' a constant expression?
  (and (not (symbol? expr))
       (or (not (pair? expr))
           (eq? (car expr) 'quote))))

(define (const-value-observed expr);; return the value of a constant expression
  (if (pair? expr);; then it must be a quoted constant
      (cadr expr)
      expr))

(define (quot-observed val);; make a quoted constant whose value is 'val'
  (list 'quote val))

(define (new-variables-observed parms env)
  (append (map (lambda (x) (cons x (new-variable x))) parms) env))

(define *current-num* 0)

(define (new-variable-observed name)
  (begin (observer-tick! 29) (set! *current-num* (+ *current-num* 1)))
  (string->symbol
   (string-append (symbol->string name)
                  "_"
                  (number->string *current-num*))))

;;------------------------------------------------------------------------------
;;
;; (peval proc args) will transform a procedure that is known to be called
;; with constants as some of its arguments into a specialized procedure that
;; is 'equivalent' but accepts only the non-constant parameters.  'proc' is the
;; list representation of a lambda-expression and 'args' is a list of values,
;; one for each parameter of the lambda-expression.  A special value (i.e.
;; 'not-constant') is used to indicate an argument that is not a constant.
;; The returned procedure is one that has as parameters the parameters of the
;; original procedure which are NOT passed constants.  Constants will have been
;; substituted for the constant parameters that are referenced in the body
;; of the procedure.
;;
;; For example:
;;
;;   (peval
;;     '(lambda (x y z) (f z x y));; the procedure
;;     (list 1 not-constant #t));; the knowledge about x, y and z
;;
;; will return: (lambda (y) (f '#t '1 y))

(define (peval-observed proc args)
  (simplify!
   (let ((parms (cadr proc));; get the parameter list
         (body (caddr proc)));; get the body of the procedure
     (list 'lambda
           (remove-constant parms args);; remove the constant parameters
           (beta-subst;; in the body, replace variable refs to the constant
            body;; parameters by the corresponding constant
            (map2 (lambda (x y) (if (not-constant? y) '(()) (cons x (quot y))))
                  parms
                  args))))))

(define not-constant (list '?));; special value indicating non-constant parms.

(define (not-constant?-observed x) (eq? x not-constant))

(define (remove-constant-observed l a);; remove from list 'l' all elements whose
  (cond ((null? l);; corresponding element in 'a' is a constant
         '())
        ((not-constant? (car a))
         (cons (car l) (remove-constant (cdr l) (cdr a))))
        (else
         (remove-constant (cdr l) (cdr a)))))

(define (extract-constant-observed l a);; extract from list 'l' all elements whose
  (cond ((null? l);; corresponding element in 'a' is a constant
         '())
        ((not-constant? (car a))
         (extract-constant (cdr l) (cdr a)))
        (else
         (cons (car l) (extract-constant (cdr l) (cdr a))))))

(define (beta-subst-observed exp env);; return a modified 'exp' where each var named in
  (define (bs exp);; 'env' is replaced by the corresponding expr (it
    (cond ((const-expr? exp);; is assumed that the code has been alphatized)
           (quot (const-value exp)))
          ((symbol? exp)
           (let ((x (assq exp env)))
             (if x (cdr x) exp)))
          ((or (eq? (car exp) 'if) (eq? (car exp) 'begin))
           (cons (car exp) (map bs (cdr exp))))
          ((or (eq? (car exp) 'let) (eq? (car exp) 'letrec))
           (list (car exp)
                 (map (lambda (x) (list (car x) (bs (cadr x)))) (cadr exp))
                 (bs (caddr exp))))
          ((eq? (car exp) 'lambda)
           (list 'lambda
                 (cadr exp)
                 (bs (caddr exp))))
          (else
           (map bs exp))))
  (bs exp))

;;------------------------------------------------------------------------------
;;
;; The expression simplifier.

(define (simplify!-observed exp);; simplify the expression 'exp' destructively (it
  ;; is assumed that the code has been alphatized)
  (define (simp! where env)

    (define (s! where)
      (let ((exp (car where)))

        (cond ((const-expr? exp));; leave constants the way they are

              ((symbol? exp));; leave variable references the way they are

              ((eq? (car exp) 'if);; dead code removal for conditionals
               (s! (cdr exp));; simplify the predicate
               (if (const-expr? (cadr exp));; is the predicate a constant?
                   (begin
                     (begin (observer-tick! 30) (set-car! where
                               (if (memq (const-value (cadr exp)) '(#f ()));; false?
                                   (if (= (length exp) 3) ''() (cadddr exp))
                                   (caddr exp))))
                     (s! where))
                   (for-each! s! (cddr exp))));; simplify consequent and alt.

              ((eq? (car exp) 'begin)
               (for-each! s! (cdr exp))
               (let loop ((exps exp));; remove all useless expressions
                 (if (not (null? (cddr exps)));; not last expression?
                     (let ((x (cadr exps)))
                       (loop (if (or (const-expr? x)
                                     (symbol? x)
                                     (and (pair? x) (eq? (car x) 'lambda)))
                                 (begin (begin (observer-tick! 31) (set-cdr! exps (cddr exps))) exps)
                                 (cdr exps))))))
               (if (null? (cddr exp));; only one expression in the begin?
                   (begin (observer-tick! 32) (set-car! where (cadr exp)))))

              ((or (eq? (car exp) 'let) (eq? (car exp) 'letrec))
               (let ((new-env (cons exp env)))
                 (define (keep i)
                   (if (>= i (length (cadar where)))
                       '()
                       (let* ((var (car (list-ref (cadar where) i)))
                              (val (cadr (assq var (cadar where))))
                              (refs (ref-count (car where) var))
                              (self-refs (ref-count val var))
                              (total-refs (- (car refs) (car self-refs)))
                              (oper-refs (- (cadr refs) (cadr self-refs))))
                         (cond ((= total-refs 0)
                                (keep (+ i 1)))
                               ((or (const-expr? val)
                                    (symbol? val)
                                    (and (pair? val)
                                         (eq? (car val) 'lambda)
                                         (= total-refs 1)
                                         (= oper-refs 1)
                                         (= (car self-refs) 0))
                                    (and (caddr refs)
                                         (= total-refs 1)))
                                (begin (observer-tick! 33) (set-car! where
                                          (beta-subst (car where)
                                                      (list (cons var val)))))
                                (keep (+ i 1)))
                               (else
                                (cons var (keep (+ i 1))))))))
                 (simp! (cddr exp) new-env)
                 (for-each! (lambda (x) (simp! (cdar x) new-env)) (cadr exp))
                 (let ((to-keep (keep 0)))
                   (if (< (length to-keep) (length (cadar where)))
                       (begin
                         (if (null? to-keep)
                             (begin (observer-tick! 34) (set-car! where (caddar where)))
                             (begin (observer-tick! 35) (set-car! (cdar where)
                                       (map (lambda (v) (assq v (cadar where))) to-keep))))
                         (s! where))
                       (if (null? to-keep)
                           (begin (observer-tick! 36) (set-car! where (caddar where))))))))

              ((eq? (car exp) 'lambda)
               (simp! (cddr exp) (cons exp env)))

              (else
               (for-each! s! exp)
               (cond ((symbol? (car exp));; is the operator position a var ref?
                      (let ((frame (binding-frame (car exp) env)))
                        (if frame;; is it a bound variable?
                            (let ((proc (bound-expr (car exp) frame)))
                              (if (and (pair? proc)
                                       (eq? (car proc) 'lambda)
                                       (some? const-expr? (cdr exp)))
                                  (let* ((args (arg-pattern (cdr exp)))
                                         (new-proc (peval proc args))
                                         (new-args (remove-constant (cdr exp) args)))
                                    (begin (observer-tick! 37) (set-car! where
                                              (cons (add-binding new-proc frame (car exp))
                                                    new-args))))))
                            (begin (observer-tick! 38) (set-car! where
                                      (constant-fold-global (car exp) (cdr exp)))))))
                     ((not (pair? (car exp))))
                     ((eq? (caar exp) 'lambda)
                      (begin (observer-tick! 39) (set-car! where
                                (list 'let
                                      (map2 list (cadar exp) (cdr exp))
                                      (caddar exp))))
                      (s! where)))))))

    (s! where))

  (define (remove-empty-calls! where env)

    (define (rec! where)
      (let ((exp (car where)))

        (cond ((const-expr? exp))
              ((symbol? exp))
              ((eq? (car exp) 'if)
               (rec! (cdr exp))
               (rec! (cddr exp))
               (rec! (cdddr exp)))
              ((eq? (car exp) 'begin)
               (for-each! rec! (cdr exp)))
              ((or (eq? (car exp) 'let) (eq? (car exp) 'letrec))
               (let ((new-env (cons exp env)))
                 (remove-empty-calls! (cddr exp) new-env)
                 (for-each! (lambda (x) (remove-empty-calls! (cdar x) new-env))
                            (cadr exp))))
              ((eq? (car exp) 'lambda)
               (rec! (cddr exp)))
              (else
               (for-each! rec! (cdr exp))
               (if (and (null? (cdr exp)) (symbol? (car exp)))
                   (let ((frame (binding-frame (car exp) env)))
                     (if frame;; is it a bound variable?
                         (let ((proc (bound-expr (car exp) frame)))
                           (if (and (pair? proc)
                                    (eq? (car proc) 'lambda))
                               (begin
                                 (begin (observer-tick! 40) (set! changed? #t))
                                 (begin (observer-tick! 41) (set-car! where (caddr proc)))))))))))))

    (rec! where))

  (define changed? #f)

  (let ((x (list exp)))
    (let loop ()
      (begin (observer-tick! 42) (set! changed? #f))
      (simp! x '())
      (remove-empty-calls! x '())
      (if changed? (loop) (car x)))))

(define (ref-count-observed exp var);; compute how many references to variable 'var'
  (let ((total 0);; are contained in 'exp'
        (oper 0)
        (always-evaled #t))
    (define (rc exp ae)
      (cond ((const-expr? exp))
            ((symbol? exp)
             (if (eq? exp var)
                 (begin
                   (begin (observer-tick! 43) (set! total (+ total 1)))
                   (begin (observer-tick! 44) (set! always-evaled (and ae always-evaled))))))
            ((eq? (car exp) 'if)
             (rc (cadr exp) ae)
             (for-each (lambda (x) (rc x #f)) (cddr exp)))
            ((eq? (car exp) 'begin)
             (for-each (lambda (x) (rc x ae)) (cdr exp)))
            ((or (eq? (car exp) 'let) (eq? (car exp) 'letrec))
             (for-each (lambda (x) (rc (cadr x) ae)) (cadr exp))
             (rc (caddr exp) ae))
            ((eq? (car exp) 'lambda)
             (rc (caddr exp) #f))
            (else
             (for-each (lambda (x) (rc x ae)) exp)
             (if (symbol? (car exp))
                 (if (eq? (car exp) var) (begin (observer-tick! 45) (set! oper (+ oper 1))))))))
    (rc exp #t)
    (list total oper always-evaled)))

(define (binding-frame-observed var env)
  (cond ((null? env) #f)
        ((or (eq? (caar env) 'let) (eq? (caar env) 'letrec))
         (if (assq var (cadar env)) (car env) (binding-frame var (cdr env))))
        ((eq? (caar env) 'lambda)
         (if (memq var (cadar env)) (car env) (binding-frame var (cdr env))))
        (else
         (error #f "ill-formed environment"))))

(define (bound-expr-observed var frame)
  (cond ((or (eq? (car frame) 'let) (eq? (car frame) 'letrec))
         (cadr (assq var (cadr frame))))
        ((eq? (car frame) 'lambda)
         not-constant)
        (else
         (error #f "ill-formed frame"))))

(define (add-binding-observed val frame name)
  (define (find-val val bindings)
    (cond ((null? bindings) #f)
          ((equal? val (cadar bindings));; *kludge* equal? is not exactly what
           (caar bindings));; we want...
          (else
           (find-val val (cdr bindings)))))
  (or (find-val val (cadr frame))
      (let ((var (new-variable name)))
        (begin (observer-tick! 46) (set-cdr! (get-last-pair (cadr frame)) (list (list var val))))
        var)))

(define (for-each!-observed proc! l);; call proc! on each CONS CELL in the list 'l'
  (if (not (null? l))
      (begin (proc! l) (for-each! proc! (cdr l)))))

(define (arg-pattern-observed exps);; return the argument pattern (i.e. the list of
  (if (null? exps);; constants in 'exps' but with the not-constant
      '();; value wherever the corresponding expression in
      (cons (if (const-expr? (car exps));; 'exps' is not a constant)
                (const-value (car exps))
                not-constant)
            (arg-pattern (cdr exps)))))

;;------------------------------------------------------------------------------
;;
;; Knowledge about primitive procedures.

(define *primitives*
  (list
   (cons 'car (lambda (args)
                (and (= (length args) 1)
                     (pair? (car args))
                     (quot (car (car args))))))
   (cons 'cdr (lambda (args)
                (and (= (length args) 1)
                     (pair? (car args))
                     (quot (cdr (car args))))))
   (cons '+ (lambda (args)
              (and (xevery? number? args)
                   (quot (sum args 0)))))
   (cons '* (lambda (args)
              (and (xevery? number? args)
                   (quot (product args 1)))))
   (cons '- (lambda (args)
              (and (> (length args) 0)
                   (xevery? number? args)
                   (quot (if (null? (cdr args))
                             (- (car args))
                             (- (car args) (sum (cdr args) 0)))))))
   (cons '/ (lambda (args)
              (and (> (length args) 1)
                   (xevery? number? args)
                   (quot (if (null? (cdr args))
                             (/ (car args))
                             (/ (car args) (product (cdr args) 1)))))))
   (cons '< (lambda (args)
              (and (= (length args) 2)
                   (xevery? number? args)
                   (quot (< (car args) (cadr args))))))
   (cons '= (lambda (args)
              (and (= (length args) 2)
                   (xevery? number? args)
                   (quot (= (car args) (cadr args))))))
   (cons '> (lambda (args)
              (and (= (length args) 2)
                   (xevery? number? args)
                   (quot (> (car args) (cadr args))))))
   (cons 'eq? (lambda (args)
                (and (= (length args) 2)
                     (quot (eq? (car args) (cadr args))))))
   (cons 'not (lambda (args)
                (and (= (length args) 1)
                     (quot (not (car args))))))
   (cons 'null? (lambda (args)
                  (and (= (length args) 1)
                       (quot (null? (car args))))))
   (cons 'pair? (lambda (args)
                  (and (= (length args) 1)
                       (quot (pair? (car args))))))
   (cons 'symbol? (lambda (args)
                    (and (= (length args) 1)
                         (quot (symbol? (car args))))))
   )
  )

(define (sum-observed lst n)
  (if (null? lst)
      n
      (sum (cdr lst) (+ n (car lst)))))

(define (product-observed lst n)
  (if (null? lst)
      n
      (product (cdr lst) (* n (car lst)))))

(define (reduce-global-observed name args)
  (let ((x (assq name *primitives*)))
    (and x ((cdr x) args))))

(define (constant-fold-global-observed name exprs)

  (define (flatten args op)
    (cond ((null? args)
           '())
          ((and (pair? (car args)) (eq? (caar args) op))
           (append (flatten (cdar args) op) (flatten (cdr args) op)))
          (else
           (cons (car args) (flatten (cdr args) op)))))

  (let ((args (if (or (eq? name '+) (eq? name '*));; associative ops
                  (flatten exprs name)
                  exprs)))
    (or (and (xevery? const-expr? args)
             (reduce-global name (map const-value args)))
        (let ((pattern (arg-pattern args)))
          (let ((non-const (remove-constant args pattern))
                (const (map const-value (extract-constant args pattern))))
            (cond ((eq? name '+);; + is commutative
                   (let ((x (reduce-global '+ const)))
                     (if x
                         (let ((y (const-value x)))
                           (cons '+
                                 (if (= y 0) non-const (cons x non-const))))
                         (cons name args))))
                  ((eq? name '*);; * is commutative
                   (let ((x (reduce-global '* const)))
                     (if x
                         (let ((y (const-value x)))
                           (cons '*
                                 (if (= y 1) non-const (cons x non-const))))
                         (cons name args))))
                  ((eq? name 'cons)
                   (cond ((and (const-expr? (cadr args))
                               (null? (const-value (cadr args))))
                          (list 'list (car args)))
                         ((and (pair? (cadr args))
                               (eq? (car (cadr args)) 'list))
                          (cons 'list (cons (car args) (cdr (cadr args)))))
                         (else
                          (cons name args))))
                  (else
                   (cons name args))))))))

;;------------------------------------------------------------------------------
;;
;; Examples:

(define (try-peval-observed proc args)
  (partial-evaluate proc args))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example1
  '(lambda (a b c)
     (if (null? a) b (+ (car a) c))))

;;(try-peval example1 (list '(10 11) not-constant '1))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example2
  '(lambda (x y)
     (let ((q (lambda (a b) (if (< a 0) b (- 10 b)))))
       (if (< x 0) (q (- y) (- x)) (q y x)))))

;;(try-peval example2 (list not-constant '1))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example3
  '(lambda (l n)
     (letrec ((add-list
               (lambda (l n)
                 (if (null? l)
                     '()
                     (cons (+ (car l) n) (add-list (cdr l) n))))))
       (add-list l n))))

;;(try-peval example3 (list not-constant '1))

;;(try-peval example3 (list '(1 2 3) not-constant))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example4
  '(lambda (exp env)
     (letrec ((eval
               (lambda (exp env)
                 (letrec ((eval-list
                           (lambda (l env)
                             (if (null? l)
                                 '()
                                 (cons (eval (car l) env)
                                       (eval-list (cdr l) env))))))
                   (if (symbol? exp) (lookup exp env)
                       (if (not (pair? exp)) exp
                           (if (eq? (car exp) 'quote) (car (cdr exp))
                               (apply (eval (car exp) env)
                                      (eval-list (cdr exp) env)))))))))
       (eval exp env))))

;;(try-peval example4 (list 'x not-constant))

;;(try-peval example4 (list '(f 1 2 3) not-constant))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example5
  '(lambda (a b)
     (letrec ((funct
               (lambda (x)
                 (+ x b (if (< x 1) 0 (funct (- x 1)))))))
       (funct a))))

;;(try-peval example5 (list '5 not-constant))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example6
  '(lambda ()
     (letrec ((fib
               (lambda (x)
                 (if (< x 2) x (+ (fib (- x 1)) (fib (- x 2)))))))
       (fib 10))))

;;(try-peval example6 '())

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example7
  '(lambda (input)
     (letrec ((copy (lambda (in)
                      (if (pair? in)
                          (cons (copy (car in))
                                (copy (cdr in)))
                          in))))
       (copy input))))

;;(try-peval example7 (list '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define example8
  '(lambda (input)
     (letrec ((reverse (lambda (in result)
                         (if (pair? in)
                             (reverse (cdr in) (cons (car in) result))
                             result))))
       (reverse input '()))))

;;(try-peval example8 (list '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))

;; . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .

(define (test-observed input1 input2)
  (begin (observer-tick! 47) (set! *current-num* 0))
  (list (try-peval example1 (list '(10 11) not-constant '1))
        (try-peval example2 (list not-constant '1))
        (try-peval example3 (list not-constant '1))
        (try-peval example3 (list '(1 2 3) not-constant))
        (try-peval example4 (list 'x not-constant))
        (try-peval example4 (list '(f 1 2 3) not-constant))
        (try-peval example5 (list '5 not-constant))
        (try-peval example6 '())
        (try-peval
         example7
         (list '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))
        (try-peval input1 input2)))


(define (xevery? pred? l)
  (observer-tick! 0) (xevery?-observed pred? l))
(define (some? pred? l)
  (observer-tick! 1) (some?-observed pred? l))
(define (map2 f l1 l2)
  (observer-tick! 2) (map2-observed f l1 l2))
(define (get-last-pair l)
  (observer-tick! 3) (get-last-pair-observed l))
(define (partial-evaluate proc args)
  (observer-tick! 4) (partial-evaluate-observed proc args))
(define (alphatize exp env)
  (observer-tick! 5) (alphatize-observed exp env))
(define (const-expr? expr)
  (observer-tick! 6) (const-expr?-observed expr))
(define (const-value expr)
  (observer-tick! 7) (const-value-observed expr))
(define (quot val)
  (observer-tick! 8) (quot-observed val))
(define (new-variables parms env)
  (observer-tick! 9) (new-variables-observed parms env))
(define (new-variable name)
  (observer-tick! 10) (observer-name name (new-variable-observed name)))
(define (peval proc args)
  (observer-tick! 11) (peval-observed proc args))
(define (not-constant? x)
  (observer-tick! 12) (not-constant?-observed x))
(define (remove-constant l a)
  (observer-tick! 13) (remove-constant-observed l a))
(define (extract-constant l a)
  (observer-tick! 14) (extract-constant-observed l a))
(define (beta-subst exp env)
  (observer-tick! 15) (beta-subst-observed exp env))
(define (simplify! exp)
  (observer-tick! 16) (simplify!-observed exp))
(define (ref-count exp var)
  (observer-tick! 17) (ref-count-observed exp var))
(define (binding-frame var env)
  (observer-tick! 18) (binding-frame-observed var env))
(define (bound-expr var frame)
  (observer-tick! 19) (bound-expr-observed var frame))
(define (add-binding val frame name)
  (observer-tick! 20) (add-binding-observed val frame name))
(define (for-each! proc! l)
  (observer-tick! 21) (for-each!-observed proc! l))
(define (arg-pattern exps)
  (observer-tick! 22) (arg-pattern-observed exps))
(define (sum lst n)
  (observer-tick! 23) (sum-observed lst n))
(define (product lst n)
  (observer-tick! 24) (product-observed lst n))
(define (reduce-global name args)
  (observer-tick! 25) (reduce-global-observed name args))
(define (constant-fold-global name exprs)
  (observer-tick! 26) (constant-fold-global-observed name exprs))
(define (try-peval proc args)
  (observer-tick! 27) (observer-case-start!)
  (observer-case-result (try-peval-observed proc args)))
(define (test input1 input2)
  (observer-tick! 28) (test-observed input1 input2))
(define configured-port (open-input-file "input.txt"))
(define configured-count-value (read configured-port))
(define input0 (let ((port configured-port)) (read port)))
(define input1 (let ((port configured-port)) (read port)))
(define (configured-count) configured-count-value)
(close-input-port configured-port)
(let ((mode (cadr (command-line))))
  (let ((result (if (string=? mode "semantics-probe") (semantics-probe) (observe-once))))
    (display "result:") (write result) (newline)))
