;; Compiling modules, linking their imports to explicit providers, and finding
;; exports. The engine uses these operations to run and replace library modules.
(define-library (snail shell wasm)
  (export
   Funcref
   Module
   Load-error
   Link-failed
   Missing-export
   load-error-message
   module-export
   unsafe-cast
   Wasm
   Compiled
   compile-bytes
   Import-kind
   Function-import
   Table-import
   Memory-import
   Global-import
   Import
   module-imports
   Provider
   Export-of
   Host-provided
   Host-if-provided
   Constant-of
   Unprovided
   link-module
   loading-program
   bind-runtime
   run-export)
  (import
   (snail core base)
   (prefix (snail runtime wasm) host-)
   (only (snail core forms) Funcref)
   (only (snail core primitive) unsafe-cast))
  (begin

    ;; ---- Host operations ----

    (effect Wasm
      ((argument-character (Fn Char → Unit))
       (argument-end (Fn → Unit))
       (compile (Fn Bytes → I32))
       (runtime-instance (Fn I32 → Unit))

       (exports-function? (Fn I32 → Bool))
       (export-function (Fn I32 → Funcref))
       (import-count (Fn I32 → I32))
       (import-at (Fn I32 I32 → I32))
       (held-length (Fn I32 → I32))
       (held-char (Fn I32 I32 → Char))
       (prepare-link (Fn I32 → Unit))
       (provide-export (Fn I32 → Bool))
       (provide-host (Fn → Bool))
       (provide-missing (Fn → Unit))
       (link-prepared (Fn → I32))
       (provide-constant (Fn I32 → Unit))

       (call-export (Fn I32 I64 → I64)))
      (default ((argument-character host-argument-character)
                (argument-end host-argument-end)
                (compile host-compile)
                (runtime-instance host-bind-runtime)

                (exports-function? host-has-export)
                (export-function host-export-function)
                (import-count host-import-count)
                (import-at host-import-at)
                (held-length host-held-length)
                (held-char host-held-char)
                (prepare-link host-prepare-link)
                (provide-export host-provide-export)
                (provide-host host-provide-host)
                (provide-missing host-provide-missing)
                (link-prepared host-link-prepared)
                (provide-constant host-provide-constant)

                (call-export host-call-export))))

    (define (send-argument (text String)) (→ Unit) (! Wasm)
      (let loop ((index 0))
        (when (< index (string-length text))
          (argument-character (string-ref text index))
          (loop (+ index 1))))
      (argument-end))

    ;; ---- Errors ----

    (enum Load-error

      (Link-failed
       ((name String)))
      (Missing-export
       ((name String)))

      )

    (define (load-error-message (error Load-error)) (→ String)
      (match error
        ((Link-failed name)
         (string-append "the module " name " imports what nothing provides at its type"))
        ((Missing-export name) (string-append "nothing is exported as " name))))

    ;; ---- Modules ----

    ;; A linked module instance.
    (record Module
      ((handle I32)))

    ;; The function the module exports as `name`.

    (define (module-export (module Module) (name String)) (→ (Result Funcref Load-error)) (! Wasm)
      (send-argument name)
      (if (exports-function? (● module handle))
          (begin (send-argument name) (Ok (export-function (● module handle))))
          (Err (Missing-export name))))

    ;; ---- Linking by hand ----

    ;; What a loader written in Snail Scheme, such as an engine linking a
    ;; program's modules, needs: a compiled module, its imports, and a link
    ;; against providers it chooses, one per import.
    (record Compiled
      ((handle I32)))

    ;; The module `bytes` hold, or none when they are not one.

    (define (compile-bytes (bytes Bytes)) (→ (Option Compiled)) (! Wasm)
      (let ((handle (compile bytes)))
        (if (< handle 0) (None) (Some (new Compiled (handle handle))))))

    (enum Import-kind
      (Function-import)
      (Table-import)
      (Memory-import)
      (Global-import))

    ;; An import: the module and field it names, and what it must be.
    (record Import
      ((from String)
       (name String)
       (kind Import-kind)))

    (define (module-imports (compiled Compiled)) (→ (List Import)) (! Wasm)
      (map (lambda (index) (import-of (● compiled handle) (i64->i32 index)))
           (iota (i32->i64 (import-count (● compiled handle))))))

    (define (import-of (module I32) (index I32)) (→ Import) (! Wasm)
      (let ((kind (import-at module index)))
        (new Import (from (held-string 0)) (name (held-string 1)) (kind (kind-of kind)))))

    (define (kind-of (code I32)) (→ Import-kind)
      (cond ((= code 0) (Function-import))
            ((= code 1) (Table-import))
            ((= code 2) (Memory-import))
            ((= code 3) (Global-import))
            (else (panic "the host answered an unknown kind of import"))))

    ;; A name the host holds, a character at a time.

    (define (held-string (which I32)) (→ String) (! Wasm)
      (string-generate (i32->i64 (held-length which))
                       (lambda (index) (held-char which (i64->i32 index)))))

    ;; What provides an import: an export of an instance, the host's own
    ;; function of the import's module and field, that function when the
    ;; host has one and otherwise nothing, a function of no arguments
    ;; answering a constant, as a linked file's handle is imported, or
    ;; nothing, a function that fails if called, as a host import a program
    ;; never calls links. A provider that is not found, an export the
    ;; instance lacks or a function the host lacks, provides nothing, and
    ;; the link fails unless another is given for the import.
    (enum Provider
      (Export-of
       ((instance Module)
        (export String)))
      (Host-provided)
      (Host-if-provided)
      (Constant-of
       ((value I32)))
      (Unprovided))

    ;; The program that loads, as an instance whose exports a loaded module
    ;; may import.

    (define (loading-program) (→ Module) (new Module (handle 0)))

    ;; Links `compiled`, called `name` in a failure, with `providers`, one
    ;; per import in import order, and initializes it when it exports
    ;; `_initialize`. The link fails when a provider names no export, the
    ;; host has no such function, an import is left without a provider, or
    ;; a provider is not of the import's type; a trap while the module
    ;; starts still ends the program.

    (define (link-module (name String) (compiled Compiled) (providers (List Provider)))
      (→ (Result Module Load-error))
      (! Wasm)
      (prepare-link (● compiled handle))
      (for-each provide providers)
      (let ((handle (link-prepared)))
        (if (< handle 0) (Err (Link-failed name)) (Ok (new Module (handle handle))))))

    (define (provide (provider Provider)) (→ Unit) (! Wasm)
      (match provider
        ((Export-of instance export)
         (send-argument export)
         (provide-export (● instance handle))
         (unit))
        ((Host-provided) (provide-host) (unit))
        ((Host-if-provided) (unless (provide-host) (provide-missing)))
        ((Constant-of value) (provide-constant value))
        ((Unprovided) (provide-missing))))

    ;; Bind the program's runtime for staging bytes and reporting errors.
    ;; Handle zero continues to identify the loader, whose own runtime stays
    ;; separate from the program it runs.
    (define (bind-runtime (runtime Module)) (→ Unit) (! Wasm)
      (runtime-instance (● runtime handle)))

    ;; Calls the function the instance exports as `name`, of no argument or
    ;; one I64, such as its `main` or a scheduler's `tasks:turn`, with
    ;; `argument`, answering its result, or 0 when it answers nothing.

    (define (run-export (instance Module) (name String) (argument I64))
      (→ (Result I64 Load-error))
      (! Wasm)
      (send-argument name)
      (if (exports-function? (● instance handle))
          (begin (send-argument name) (Ok (call-export (● instance handle) argument)))
          (Err (Missing-export name))))

    ))
