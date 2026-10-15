;; Monomorphic scalar import contracts, shared by declaration checking and Wasm
;; emission. Managed-reference imports require a concrete shared type graph.
(define-library (snail-scheme wasm-extern)
  (export parse-extern extern? extern-name extern-module extern-symbol extern-type
          extern-argument-types extern-result-type extern-physical-signature
          extern-wasm-import extern-wasm-call native-scalar-signature)
  (import (scheme base) (scheme cxr))
  (begin

    ;; ---- Complete foreign declarations ----

    (define-record-type <extern>
      (make-extern name module symbol type arguments result)
      extern?
      (name extern-name) (module extern-module) (symbol extern-symbol)
      (type extern-type) (arguments extern-argument-types) (result extern-result-type))

    (define (parse-extern form)
      (unless (and (list? form) (= (length form) 5) (eq? (car form) 'define-extern)
                   (symbol? (cadr form)) (string? (caddr form)) (string? (cadddr form)))
        (error "expected (define-extern name module symbol function-type)" form))
      (let* ((type (car (cddddr form))) (signature (extern-signature type)))
        (make-extern (cadr form) (caddr form) (cadddr form) type
                     (car signature) (cdr signature))))

    (define (extern-signature type)
      (unless (and (list? type) (pair? type) (eq? (car type) '->) (pair? (cdr type)))
        (error "extern requires a complete monomorphic function type" type))
      (let* ((parts (reverse (cdr type))) (result (car parts))
             (arguments (reverse (cdr parts))))
        (native-scalar-signature arguments result)
        (cons arguments result)))

    ;; Char and Bool retain their semantic contract while using native i32.
    ;; Reference declarations need the concrete core's shared Wasm type graph.
    ;; Reject them here: a managed reference is never a numeric resource ID.
    (define (extern-scalar-type type)
      (case type
        ((I32 Char Bool Boolean) 'i32)
        ((I64) 'i64) ((F32) 'f32) ((F64) 'f64)
        (else (error "unsupported concrete extern type" type))))

    ;; ---- Matching imports and calls ----

    (define (native-scalar-signature arguments result)
      (append (map (lambda (type) `(param ,(extern-scalar-type type)))
                   arguments)
              (if (eq? result 'Unit) '() `((result ,(extern-scalar-type result))))))

    (define (extern-physical-signature declaration)
      (native-scalar-signature (extern-argument-types declaration) (extern-result-type declaration)))

    (define (extern-wasm-import declaration identifier)
      `(import ,(extern-module declaration) ,(extern-symbol declaration)
               (func ,identifier ,@(extern-physical-signature declaration))))

    ;; Arguments are already typed Wasm expressions, in source evaluation order.
    ;; There is no argument vector, Scheme object conversion, or ABI root here.
    (define (extern-wasm-call declaration identifier arguments)
      (unless (= (length arguments) (length (extern-argument-types declaration)))
        (error "extern call has the wrong number of arguments" (extern-name declaration)))
      `(call ,identifier ,@arguments))

    ;; ---- Tests ----

    (cond-expand
     (snail-tests
      (begin
        (define (check-extern expected actual)
          (unless (equal? expected actual) (error "extern test failed" expected actual)))

        (define (reject-extern form)
          (unless (guard (condition (else #t)) (parse-extern form) #f)
            (error "extern declaration should be rejected" form)))

        (define (test-scalar-imports)
          (let ((read (parse-extern '(define-extern read "io" "read" (-> I32 I32))))
                (write (parse-extern '(define-extern write "io" "write" (-> I32 Char I32)))))
            (check-extern '(import "io" "read" (func $read (param i32) (result i32)))
                          (extern-wasm-import read '$read))
            (check-extern '(import "io" "write" (func $write (param i32) (param i32) (result i32)))
                          (extern-wasm-import write '$write))
            (check-extern '(call $write (i32.const 7) (i32.const 955))
                          (extern-wasm-call write '$write '((i32.const 7) (i32.const 955))))))

        (define (test-other-signatures)
          (check-extern '(import "m" "f" (func $f (param i64) (param f32) (result f64)))
                        (extern-wasm-import
                         (parse-extern '(define-extern f "m" "f" (-> I64 F32 F64))) '$f))
          (check-extern '(import "m" "f" (func $f))
                        (extern-wasm-import
                         (parse-extern '(define-extern f "m" "f" (-> Unit))) '$f)))

        (define (test-invalid-declarations)
          (for-each reject-extern
                    '((define-extern x "m" "f") (define-extern x m "f" (-> I32))
                      (define-extern x "m" "f" (->)) (define-extern x "m" "f" (-> Unit I32))
                      (define-extern x "m" "f" (All (A) (-> A A)))
                      (define-extern x "m" "f" (-> Any Any))
                      (define-extern x "m" "f" (-> StringRef I32)))))

        (define (test-wasm-extern)
          (test-scalar-imports) (test-other-signatures) (test-invalid-declarations))))
     (else))
    )
  (cond-expand (snail-tests (export test-wasm-extern)) (else)))
