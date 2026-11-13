;; The typed source forms erased for the Chez bootstrap. This host executes
;; compiler code only; source programs are checked and compiled to WasmGC.
(library (snail stage0 forms)
  (export define : type ann struct enum match effect handle ● set! replace! test-forms)
  (import
   (rename (chezscheme) (define scheme-define) (set! scheme-set!)))

  ;; ---- Typed definitions ----

  (meta scheme-define (syntax-list form)
        (syntax-case form () [() '()] [(head . rest) (cons #'head (syntax-list #'rest))]))

  (meta scheme-define (head-name head)
        (syntax-case head () [(name . parameters) #'name] [name #'name]))

  (meta scheme-define (header-clause? form)
        (syntax-case form ()
          [(name . rest) (memq (syntax->datum #'name) '(→ ! ∀ ⊨))]
          [_ #f]))

  (meta scheme-define (definition-body forms)
        (if (and (pair? forms) (header-clause? (car forms)))
            (definition-body (cdr forms)) forms))

  (meta scheme-define (parameter-names form)
        (syntax-case form ()
          [() #'()]
          [((name type) . rest) #`(name . #,(parameter-names #'rest))]
          [(name . rest) #`(name . #,(parameter-names #'rest))]
          [name #'name]))

  (define-syntax define
    (lambda (form)
      (syntax-case form ()
        [(_ (name . parameters) . body)
         #`(scheme-define (name . #,(parameter-names #'parameters))
             #,@(definition-body (syntax-list #'body)))]
        [(_ name . body)
         #`(scheme-define name #,@(definition-body (syntax-list #'body)))])))

  (define-syntax : (syntax-rules () [(_ . rest) (begin)]))
  (define-syntax ann (syntax-rules () [(_ expression type) expression]))
  (define-syntax type
    (lambda (form)
      (syntax-case form ()
        [(_ head . rest)
         (with-syntax ([name (head-name #'head)]) #'(scheme-define name 'name))])))

  ;; ---- Records ----

  ;; A constructor identifies the record. Every field is a mutable vector
  ;; slot; pure replacement copies only the outer vector, preserving aliases.
  (scheme-define record-fields (make-eq-hashtable))
  (scheme-define (register-fields! constructor labels)
    (hashtable-set! record-fields constructor labels))
  (scheme-define (field-index value label)
    (let loop ([labels (hashtable-ref record-fields (vector-ref value 0) '())] [index 1])
      (cond [(null? labels) (error '● "no such field" label)]
            [(eq? label (car labels)) index]
            [else (loop (cdr labels) (+ index 1))])))
  (scheme-define (field-of value label) (vector-ref value (field-index value label)))
  (scheme-define (replace-field! record label value)
    (let* ([index (field-index record label)] [old (vector-ref record index)])
      (vector-set! record index value)
      old))

  (meta scheme-define (joined-name name field suffix)
        (datum->syntax name
                       (string->symbol (string-append (symbol->string (syntax->datum name)) "-"
                                                      (symbol->string (syntax->datum field))
                                                      suffix))))
  (meta scheme-define (field-name field)
        (syntax-case field () [(name . rest) #'name]))
  (meta scheme-define (field-definitions name field index)
        (with-syntax ([replace (joined-name name field "-set")]
                      [index (datum->syntax name index)])
          (syntax-list
           #'((scheme-define (replace value content)
                (let ([copy (vector-copy value)]) (vector-set! copy index content) copy))))))

  (meta scheme-define (record-definitions name fields struct?)
        (let ([names (map field-name fields)])
          (append (list #`(scheme-define (#,name #,@names) (vector #,name #,@names))
                        #`(scheme-define #,(car (generate-temporaries '(registered)))
                            (register-fields! #,name '(#,@names))))
                  (let loop ([names names] [index 1])
                    (if (null? names) '()
                        (append (if struct? (field-definitions name (car names) index) '())
                                (loop (cdr names) (+ index 1))))))))

  (define-syntax struct
    (lambda (form)
      (syntax-case form ()
        [(_ head (field ...) . rest)
         #`(begin #,@(record-definitions (head-name #'head) (syntax-list #'(field ...)) #t))])))

  (define-syntax enum
    (lambda (form)
      (syntax-case form ()
        [(_ head . cases)
         (let ([name (head-name #'head)])
           #`(begin (scheme-define #,name '#,name)
                    #,@(apply append
                              (map (lambda (case)
                                     (syntax-case case ()
                                       [(name) (record-definitions #'name '() #f)]
                                       [(name (field ...))
                                        (record-definitions #'name
                                                            (syntax-list #'(field ...))
                                                            #f)]))
                                   (syntax-list #'cases)))))])))

  (define-syntax ●
    (syntax-rules ()
      [(_ value label) (field-of value 'label)]
      [(_ value label next ...) (● (● value label) next ...)]))
  (define-syntax set!
    (syntax-rules (●)
      [(_ (● record label) value)
       (let ([object record] [content value])
         (vector-set! object (field-index object 'label) content))]
      [(_ (● record label next ...) value) (set! (● (● record label) next ...) value)]
      [(_ name value) (scheme-set! name value)]))
  (define-syntax replace!
    (syntax-rules (●)
      [(_ (● record label) value) (replace-field! record 'label value)]
      [(_ (● record label next ...) value) (replace! (● (● record label) next ...) value)]))

  ;; ---- Matching ----

  ;; Test every path before binding names. Failed clauses never expose a
  ;; partly matched value; constructor identity distinguishes nominal cases.
  (meta scheme-define (pattern-test pattern value)
        (syntax-case pattern (quote)
          [name (identifier? #'name) #t]
          [(quote datum) #`(equal? #,value 'datum)]
          [(constructor . fields)
           (let ([name (syntax->datum #'constructor)] [fields (syntax-list #'fields)])
             (cond [(eq? name 'Nil) #`(null? #,value)]
                   [(eq? name 'Cons)
                    #`(and (pair? #,value)
                           #,(pattern-test (car fields) #`(car #,value))
                           #,(pattern-test (cadr fields) #`(cdr #,value)))]
                   [else #`(and (vector? #,value) (eq? (vector-ref #,value 0) constructor)
                                #,@(let loop ([fields fields] [index 1])
                                     (if (null? fields) '()
                                         (cons
                                          (pattern-test (car fields) #`(vector-ref #,value #,index))
                                          (loop (cdr fields) (+ index 1))))))]))]
          [literal #`(equal? #,value literal)]))

  (meta scheme-define (pattern-bindings pattern value)
        (syntax-case pattern (quote)
          [name (identifier? #'name)
                (if (eq? (syntax->datum #'name) '_) '() (list #`(name #,value)))]
          [(quote datum) '()]
          [(constructor . fields)
           (let ([name (syntax->datum #'constructor)] [fields (syntax-list #'fields)])
             (cond [(eq? name 'Nil) '()]
                   [(eq? name 'Cons)
                    (append (pattern-bindings (car fields) #`(car #,value))
                            (pattern-bindings (cadr fields) #`(cdr #,value)))]
                   [else (let loop ([fields fields] [index 1])
                           (if (null? fields) '()
                               (append
                                (pattern-bindings (car fields) #`(vector-ref #,value #,index))
                                (loop (cdr fields) (+ index 1)))))]))]
          [_ '()]))

  (define-syntax match
    (lambda (form)
      (syntax-case form ()
        [(_ expression (pattern body ...) ...)
         (let ([value (car (generate-temporaries '(scrutinee)))])
           #`(let ([#,value expression])
               (cond #,@(map (lambda (pattern body)
                               #`(#,(pattern-test pattern value)
                                   (let (#,@(pattern-bindings pattern value))
                                     #,@(syntax-list body))))
                             (syntax-list #'(pattern ...)) (syntax-list #'((body ...) ...)))
                     [else (error 'match "no clause matched" #,value)])))])))

  ;; ---- Compiler failures ----

  ;; The source compiler uses only abortive control effects at stage zero.
  ;; Each handler records the complete outside context. Returning operations
  ;; must hide inner handlers of other effects too, just as Wasm evidence does.
  (scheme-define handlers (make-parameter '()))
  (scheme-define (find-handler effect operation)
    (let loop ([stack (handlers)])
      (cond [(null? stack) (error 'effect "unhandled operation" operation)]
            [(eq? effect (caar stack)) (car stack)]
            [else (loop (cdr stack))])))
  ;; Chez's private escape unwinds to the handler before invoking its body.
  (scheme-define (perform effect operation arguments)
    (let ([handler (find-handler effect operation)])
      ((cadr handler) (lambda () (apply (cdr (assq operation (cadddr handler))) arguments)))))
  (scheme-define (perform-returning effect operation arguments)
    (let ([handler (find-handler effect operation)])
      (parameterize ([handlers (caddr handler)])
        (apply (cdr (assq operation (cadddr handler))) arguments))))
  (scheme-define (cannot-resume answer) (error 'resume "stage zero cannot resume"))
  (scheme-define (handling effect implementations body)
    ((call/cc (lambda (escape)
                (let* ([node (list effect escape (handlers) implementations)]
                       [value (parameterize ([handlers (cons node (handlers))]) (body))])
                  (lambda () value))))))
  (define-syntax handle
    (syntax-rules ()
      [(_ effect ((operation implementation) ...) body ...)
       (handling effect (list (cons 'operation implementation) ...) (lambda () body ...))]))
  (define-syntax effect
    (lambda (form)
      (syntax-case form ()
        [(_ name (operation ...) . rest)
         #`(begin (scheme-define name (gensym))
                  #,@(map (lambda (operation)
                            (syntax-case operation (ctl)
                              [(ctl method signature)
                               (let* ([signature (syntax->datum #'signature)]
                                      [answer (memq '→ signature)])
                                 #`(scheme-define (method . arguments)
                                     (perform name 'method
                                              #,(if (and answer (eq? (cadr answer) 'Never))
                                                    #'arguments
                                                    #'(append arguments (list cannot-resume))))))]
                              [(method signature)
                               #'(scheme-define (method . arguments)
                                   (perform-returning name 'method arguments))]
                              [_ (syntax-error operation "expected an effect operation")]))
                          (syntax-list #'(operation ...))))])))
  ;; ---- Tests ----

  (struct Counter
    ((label String)
     (value I64)))
  (enum Documented (Present ((value I64)))
        (Absent))
  (effect Stop ((ctl stop (Fn I64 → Never))))
  (effect Read ((read-value (Fn → I64))))
  (effect Observe ((observe-value (Fn → I64))))
  (define (typed-sum (left I64) (right I64)) (→ I64) (+ left right))
  (scheme-define (test-forms)
    (let* ([record (Counter "before" 1)] [alias record]
           [changed (Counter-label-set record "after")])
      (set! (● alias value) 2)
      (unless (and (= (● record value) 2) (= (● changed value) 1)
                   (= (replace! (● record value) 3) 2) (= (● alias value) 3)
                   (= (typed-sum 20 22) 42)
                   (= (handle Read ((read-value (lambda () 10)))
                        (handle Observe ((observe-value (lambda () (read-value))))
                          (handle Read ((read-value (lambda () 20))) (observe-value)))) 10)
                   (= (handle Read ((read-value (lambda () 10)))
                        (handle Read ((read-value (lambda () (+ 1 (read-value)))))
                          (+ 1 (read-value)))) 12)
                   (= (match (Present 7) [(Present value) value] [(Absent) 0]) 7)
                   (= (match (Absent) [(Present value) value] [(Absent) 0]) 0)
                   (= (handle Stop ((stop (lambda (value) (* 10 value))))
                        (+ 1 (guard (failure [else 0]) (stop 4)))) 40))
        (error 'test-forms "typed forms do not preserve reference semantics"))))

  )
