;; Literal objects are module data. Dependencies precede their users, so both
;; WasmGC constant expressions consume this shared, dependency-ordered graph.
(define-library (snail-scheme wasm-literals)
  (export make-literal-pool literal-reference literal-declarations)
  (import (scheme base) (scheme cxr) (scheme complex) (scheme hash-table))
  (begin

    ;; ---- Pool and object identity ----

    (define-record-type <pool>
      (make-pool entries definitions symbols symbol-count count) pool?
      (entries pool-entries set-pool-entries!)
      (definitions pool-definitions set-pool-definitions!)
      (symbols pool-symbols set-pool-symbols!)
      (symbol-count pool-symbol-count set-pool-symbol-count!)
      (count pool-count set-pool-count!))

    (define (make-literal-pool) (make-pool (make-hash-table eq?) '() '() 0 0))
    (define (literal-name index) (string->symbol (string-append "$literal" (number->string index))))
    (define (compound? value)
      (or (pair? value) (vector? value) (string? value) (symbol? value) (bytevector? value)))

    ;; Never merge merely equal mutable objects. A reserved entry precedes its
    ;; children; its ready flag distinguishes sharing from an unsupported cycle.
    (define (reserve! pool value)
      (let ((entry (list value (literal-name (pool-count pool)) #f)))
        (hash-table-set! (pool-entries pool) value entry)
        (set-pool-count! pool (+ 1 (pool-count pool)))
        entry))

    (define (children value)
      (cond ((pair? value) (list (car value) (cdr value)))
            ((vector? value) (vector->list value))
            (else '())))

    ;; An explicit work list also handles long lists without using the host's
    ;; call stack. Source datum labels are not yet part of the bootstrap reader.
    (define (register! value pool)
      (let loop ((work (list (cons 'visit value))))
        (unless (null? work)
          (let* ((task (car work)) (value (cdr task)))
            (cond ((eq? (car task) 'finish) (finish! value pool) (loop (cdr work)))
                  ((not (compound? value)) (loop (cdr work)))
                  ((hash-table-ref/default (pool-entries pool) value #f)
                   => (lambda (entry)
                        (unless (caddr entry) (error "cyclic literals require datum-label support"))
                        (loop (cdr work))))
                  (else
                   (let ((entry (reserve! pool value)))
                     (loop (append (map (lambda (child) (cons 'visit child)) (children value))
                                   (cons (cons 'finish entry) (cdr work)))))))))))

    (define (finish! entry pool)
      (let ((value (car entry)))
        (set-pool-definitions! pool
                               (cons `(global ,(cadr entry) eqref ,(object-expression value pool))
                                     (pool-definitions pool)))
        (when (symbol? value)
          (set-pool-symbols! pool (cons value (pool-symbols pool)))
          (set-pool-symbol-count! pool (+ 1 (pool-symbol-count pool))))
        (set-car! (cddr entry) #t)))

    (define (literal-reference value pool)
      (if (compound? value)
          (begin (register! value pool) `(global.get ,(cadr (hash-table-ref/default (pool-entries pool) value #f))))
          (scalar-expression value)))

    (define (reference value pool)
      (if (compound? value) `(global.get ,(cadr (hash-table-ref/default (pool-entries pool) value #f)))
          (scalar-expression value)))

    ;; ---- Constant expressions ----

    (define (integer-expression value)
      (unless (<= -9223372036854775808 value 9223372036854775807)
        (error "integer literal outside supported signed 64-bit range" value))
      (if (<= -1073741824 value 1073741823) `(ref.i31 (i32.const ,value))
          `(struct.new $integer (i64.const ,value))))

    (define (float-expression value)
      (let ((spelling (number->string value)))
        `(f64.const ,(cond ((equal? spelling "+inf.0") 'inf)
                           ((equal? spelling "-inf.0") (string->symbol "-inf"))
                           ((equal? spelling "+nan.0") 'nan)
                           (else value)))))

    (define (scalar-expression value)
      (cond ((eq? value #f) '(global.get $false))
            ((eq? value #t) '(global.get $true))
            ((null? value) '(global.get $nil))
            ((char? value) `(struct.new $atom (i32.const ,(+ 256 (char->integer value)))))
            ((exact-integer? value) (integer-expression value))
            ((and (number? value) (not (real? value)))
             `(struct.new $complex ,(scalar-expression (real-part value))
                          ,(scalar-expression (imag-part value))))
            ((and (real? value) (inexact? value)) `(struct.new $float ,(float-expression (real-part value))))
            (else (error "unsupported literal value" value))))

    (define (text-expression text)
      `(array.new_fixed $text ,(string-length text)
                        ,@(map (lambda (character) `(i32.const ,(char->integer character)))
                               (string->list text))))

    (define (bytes-expression bytes)
      (let loop ((index (- (bytevector-length bytes) 1)) (values '()))
        (if (< index 0) `(array.new_fixed $bytes ,(bytevector-length bytes) ,@values)
            (loop (- index 1) (cons `(i32.const ,(bytevector-u8-ref bytes index)) values)))))

    (define (object-expression value pool)
      (cond ((pair? value) `(struct.new $pair ,(reference (car value) pool) ,(reference (cdr value) pool)))
            ((vector? value) `(array.new_fixed $vector ,(vector-length value)
                                               ,@(map (lambda (value) (reference value pool)) (vector->list value))))
            ((bytevector? value) `(struct.new $bytevector ,(bytes-expression value)))
            ((string? value) `(struct.new $text_object (i32.const 0) ,(text-expression value)))
            ((symbol? value)
             (when (>= (pool-symbol-count pool) 2147483648) (error "symbol ID space exhausted"))
             `(struct.new $atom (i32.const ,(- (pool-symbol-count pool) 2147483648))))))

    ;; Literal IDs form the initial prefix of the Rust registry. Names and IDs
    ;; share this one ordering; the registry installs every name before assigning
    ;; dynamic IDs. This is constant data, with no generated initializer calls.
    (define (symbol-declarations names)
      `((global $symbol_names (ref $vector)
                (array.new_fixed $vector ,(length names)
                                 ,@(map (lambda (name) `(struct.new $text_object (i32.const 0)
                                                                    ,(text-expression (symbol->string name))))
                                        (reverse names))))))

    (define (literal-declarations pool)
      (append (reverse (pool-definitions pool)) (symbol-declarations (pool-symbols pool)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm-literals)
    (import (snail-scheme test-utils))
    (begin
      (define (test-literal-identity)
        (let* ((pool (make-literal-pool)) (shared (cons 1 2))
               (root (vector shared shared (cons 1 2))) (reference (literal-reference root pool)))
          (expect (literal-reference root pool) reference)
          (expect (pool-count pool) 3)
          (expect (map cadr (reverse (pool-definitions pool))) '($literal1 $literal2 $literal0))
          (expect (cadddr (car (pool-definitions pool)))
                  '(array.new_fixed $vector 3 (global.get $literal1) (global.get $literal1) (global.get $literal2)))))

      (define (test-literal-cycles)
        (let ((value (cons 1 '())))
          (set-cdr! value value)
          (expect (guard (failure (else #t)) (literal-reference value (make-literal-pool)) #f) #t)))

      (define (test-literal-symbols)
        (let ((pool (make-literal-pool)))
          (literal-reference 'one pool) (literal-reference (string->symbol "one") pool)
          (expect (pool-count pool) 1)
          (literal-reference '#(two one) pool)
          (expect (pool-symbol-count pool) 2)
          (expect (cadddr (car (reverse (pool-definitions pool))))
                  `(struct.new $atom (i32.const ,(string->number "-2147483648"))))
          (expect (car (reverse (literal-declarations pool)))
                  `(global $symbol_names (ref $vector)
                           (array.new_fixed $vector 2
                                            (struct.new $text_object (i32.const 0) ,(text-expression "one"))
                                            (struct.new $text_object (i32.const 0) ,(text-expression "two")))))))

      (define (test-literal-floats)
        (let ((pool (make-literal-pool)))
          (for-each
           (lambda (spelling token)
             (expect (literal-reference (string->number spelling) pool)
                     `(struct.new $float (f64.const ,(string->symbol token)))))
           '("+inf.0" "-inf.0" "+nan.0") '("inf" "-inf" "nan"))))

      (define (test-literal-complex)
        (let ((value (string->number "3+4i")))
          (expect (literal-reference value (make-literal-pool))
                  '(struct.new $complex (ref.i31 (i32.const 3)) (ref.i31 (i32.const 4))))))

      (define (test-wasm-literals)
        (run-test test-literal-identity)
        (run-test test-literal-cycles)
        (run-test test-literal-symbols)
        (run-test test-literal-floats)
        (run-test test-literal-complex))))))
