;; Physical storage for lexical bindings and closure environments. Each binding
;; has one authoritative payload. A concrete payload needs both a solved type
;; and proof that its existing ingress already consumes one Scheme value.
(define-library (snail-scheme wasm-bindings)
  (export make-binding-layouts binding-layout-definitions
          binding-cell-representation binding-cell-new binding-cell-read binding-cell-write
          binding-environment-type binding-environment-read
          binding-payload-type binding-payload-default binding-payload-read)
  (import (scheme base) (scheme cxr) (snail-scheme wasm-representation))
  (begin

    ;; ---- Nullable storage and initialization ----

    ;; A reference payload may start null, even when every initialized value
    ;; has a non-null type. Readiness is separate from zero/null payload bits.
    (define (binding-payload-type representation)
      (let ((type (representation-wasm representation)))
        (if (and (pair? type) (eq? (car type) 'ref) (= (length type) 2))
            `(ref null ,(cadr type)) type)))

    (define (binding-payload-default representation)
      (let ((type (binding-payload-type representation)))
        (case type
          ((eqref) '(global.get $uninitialized))
          ((i32) '(i32.const 0)) ((i64) '(i64.const 0))
          ((f32) '(f32.const 0)) ((f64) '(f64.const 0))
          (else `(ref.null ,(caddr type))))))

    ;; These helpers never introduce single-value consumption. A raw envelope
    ;; remains raw in generic storage until its original source consumption site.
    (define (binding-payload-read value ready representation)
      (if (eq? representation 'eqref) `(call $defined ,value)
          `(block (result ,(representation-wasm representation))
                  (if (i32.eqz ,ready) (then (call $fail (i32.const 6))))
                  ,(if (equal? (binding-payload-type representation) (representation-wasm representation))
                       value `(ref.as_non_null ,value)))))

    ;; ---- Per-module layout declarations ----

    (define-record-type <binding-layouts>
      (make-layouts cells environments) binding-layouts?
      (cells layout-cells set-layout-cells!)
      (environments layout-environments set-layout-environments!))

    (define (make-binding-layouts) (make-layouts '() '()))
    (define (layout-name prefix index)
      (string->symbol (string-append "$" prefix (number->string index))))

    (define (cell-entry representation layouts)
      (or (assoc representation (layout-cells layouts))
          (let ((entry (cons representation (length (layout-cells layouts)))))
            (set-layout-cells! layouts (cons entry (layout-cells layouts))) entry)))

    (define (cell-name representation layouts)
      (if (eq? representation 'eqref) '$cell
          (layout-name "binding_cell" (cdr (cell-entry representation layouts)))))

    (define (cell-worker prefix representation layouts)
      (layout-name prefix (cdr (cell-entry representation layouts))))

    (define (binding-cell-representation representation layouts)
      `(ref ,(cell-name representation layouts)))

    ;; A lambda family has one ordered environment shape. Specialized workers
    ;; read the environment of the actual closure, never a reconstructed copy.
    (define (binding-environment-type family representations layouts)
      (let ((entry (assv family (layout-environments layouts))))
        (cond ((not entry) (set-layout-environments! layouts
                                                     (cons (cons family representations) (layout-environments layouts))))
              ((not (equal? representations (cdr entry)))
               (error "inconsistent closure family storage" family representations (cdr entry))))
        (layout-name "environment" family)))

    (define (binding-environment-read type index)
      `(struct.get ,type ,index (ref.cast (ref ,type) (local.get $env))))

    (define (environment-definition entry)
      `(type ,(layout-name "environment" (car entry))
             (struct ,@(map (lambda (representation) `(field ,(representation-wasm representation))) (cdr entry)))))

    ;; ---- Shared mutable and early-captured locations ----

    ;; Capturing a cell copies its managed reference, without reading payload or
    ;; readiness. WasmGC traces every reference field across allocation/callbacks.
    (define (binding-cell-new representation value layouts)
      (let ((type (cell-name representation layouts)))
        (if (eq? representation 'eqref)
            `(struct.new ,type ,(or value '(global.get $uninitialized)))
            `(struct.new ,type (i32.const ,(if value 1 0))
                         ,(or value (binding-payload-default representation))))))

    (define (binding-cell-read representation cell layouts)
      (if (eq? representation 'eqref)
          `(call $defined (struct.get $cell 0 (ref.cast (ref $cell) ,cell)))
          `(call ,(cell-worker "binding_read" representation layouts) ,cell)))

    ;; The incoming value is already encoded. Failed evaluation/conversion leaves
    ;; both old payload and readiness unchanged. Any successful assignment makes
    ;; the location readable, including an assignment before its initializer.
    (define (binding-cell-write representation cell value layouts)
      (if (eq? representation 'eqref)
          `(struct.set $cell 0 (ref.cast (ref $cell) ,cell) ,value)
          `(call ,(cell-worker "binding_write" representation layouts) ,cell ,value)))

    (define (cell-definition entry)
      `(type ,(layout-name "binding_cell" (cdr entry))
             (struct (field (mut i32)) (field (mut ,(binding-payload-type (car entry)))))))

    (define (cell-read-function entry)
      (let ((type (layout-name "binding_cell" (cdr entry))) (representation (car entry)))
        `(func ,(layout-name "binding_read" (cdr entry)) (param $cell (ref ,type))
               (result ,(representation-wasm representation))
               ,(binding-payload-read `(struct.get ,type 1 (local.get $cell))
                                      `(struct.get ,type 0 (local.get $cell)) representation))))

    (define (cell-write-function entry)
      (let ((type (layout-name "binding_cell" (cdr entry))))
        `(func ,(layout-name "binding_write" (cdr entry)) (param $cell (ref ,type))
               (param $value ,(representation-wasm (car entry)))
               (struct.set ,type 1 (local.get $cell) (local.get $value))
               (struct.set ,type 0 (local.get $cell) (i32.const 1)))))

    (define (binding-layout-definitions layouts)
      (let ((cells (reverse (layout-cells layouts))))
        (append (map cell-definition cells)
                (map environment-definition (reverse (layout-environments layouts)))
                (map cell-read-function cells) (map cell-write-function cells))))

    ))
