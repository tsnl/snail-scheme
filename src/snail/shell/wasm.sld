;; Compiling modules, linking their imports to explicit providers, and finding
;; exports. The engine uses these operations to run and replace library modules.
(define-library (snail shell wasm)
  (export
   Funcref
   Module
   LoadError
   LinkFailed
   MissingExport
   load-error-message
   module-export
   unsafe-cast
   Wasm
   host-wasm
   Compiled
   compile-bytes
   ImportKind
   FunctionImport
   TableImport
   MemoryImport
   GlobalImport
   Import
   module-imports
   Provider
   ExportOf
   HostProvided
   HostIfProvided
   ConstantOf
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

    (record Wasm
      ((argument-character (Fn Char → Unit ! mut))
       (argument-end (Fn → Unit ! mut))
       (compile (Fn Bytes → I32 ! mut))
       (runtime-instance (Fn I32 → Unit ! mut))
       (exports-function? (Fn I32 → Bool ! mut))
       (export-function (Fn I32 → Funcref ! mut))
       (import-count (Fn I32 → I32 ! mut))
       (import-at (Fn I32 I32 → I32 ! mut))
       (held-length (Fn I32 → I32 ! mut))
       (held-char (Fn I32 I32 → Char ! mut))
       (prepare-link (Fn I32 → Unit ! mut))
       (provide-export (Fn I32 → Bool ! mut))
       (provide-host (Fn → Bool ! mut))
       (provide-missing (Fn → Unit ! mut))
       (link-prepared (Fn → I32 ! mut))
       (provide-constant (Fn I32 → Unit ! mut))
       (call-export (Fn I32 I64 → I64 ! mut))))

    (define (argument-character (wasm Wasm) (char Char)) (→ Unit) (! mut)
      ((● wasm argument-character) char))

    (define (argument-end (wasm Wasm)) (→ Unit) (! mut)
      ((● wasm argument-end)))

    (define (compile (wasm Wasm) (bytes Bytes)) (→ I32) (! mut)
      ((● wasm compile) bytes))

    (define (runtime-instance (wasm Wasm) (n I32)) (→ Unit) (! mut)
      ((● wasm runtime-instance) n))

    (define (exports-function? (wasm Wasm) (n I32)) (→ Bool) (! mut)
      ((● wasm exports-function?) n))

    (define (export-function (wasm Wasm) (n I32)) (→ Funcref) (! mut)
      ((● wasm export-function) n))

    (define (import-count (wasm Wasm) (n I32)) (→ I32) (! mut)
      ((● wasm import-count) n))

    (define (import-at (wasm Wasm) (n-1 I32) (n-2 I32)) (→ I32) (! mut)
      ((● wasm import-at) n-1 n-2))

    (define (held-length (wasm Wasm) (n I32)) (→ I32) (! mut)
      ((● wasm held-length) n))

    (define (held-char (wasm Wasm) (n-1 I32) (n-2 I32)) (→ Char) (! mut)
      ((● wasm held-char) n-1 n-2))

    (define (prepare-link (wasm Wasm) (n I32)) (→ Unit) (! mut)
      ((● wasm prepare-link) n))

    (define (provide-export (wasm Wasm) (n I32)) (→ Bool) (! mut)
      ((● wasm provide-export) n))

    (define (provide-host (wasm Wasm)) (→ Bool) (! mut)
      ((● wasm provide-host)))

    (define (provide-missing (wasm Wasm)) (→ Unit) (! mut)
      ((● wasm provide-missing)))

    (define (link-prepared (wasm Wasm)) (→ I32) (! mut)
      ((● wasm link-prepared)))

    (define (provide-constant (wasm Wasm) (n I32)) (→ Unit) (! mut)
      ((● wasm provide-constant) n))

    (define (call-export (wasm Wasm) (n-1 I32) (n-2 I64)) (→ I64) (! mut)
      ((● wasm call-export) n-1 n-2))

    ;; The host's own engine: the page's or Node's WebAssembly.
    (define (host-wasm) (→ Wasm)
      (new Wasm
        (argument-character host-argument-character)
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
        (call-export host-call-export)))

    (define (send-argument (wasm Wasm) (text String)) (→ Unit) (! mut)
      (let loop ((index 0))
        (when (< index (string-length text))
          (argument-character wasm (string-ref text index))
          (loop (+ index 1))))
      (argument-end wasm))

    ;; ---- Errors ----

    (enum LoadError

      (LinkFailed
       ((name String)))
      (MissingExport
       ((name String)))

      )

    (define (load-error-message (error LoadError)) (→ String)
      (match error
        ((LinkFailed name)
         (string-append "the module " name " imports what nothing provides at its type"))
        ((MissingExport name) (string-append "nothing is exported as " name))))

    ;; ---- Modules ----

    ;; A linked module instance.
    (record Module
      ((handle I32)))

    ;; The function the module exports as `name`.

    (define (module-export (wasm Wasm) (module Module) (name String))
      (→ (Result Funcref LoadError))
      (! mut)
      (send-argument wasm name)
      (if (exports-function? wasm (● module handle))
          (begin (send-argument wasm name) (Ok (export-function wasm (● module handle))))
          (Err (MissingExport name))))

    ;; ---- Linking by hand ----

    ;; What a loader written in `snail-scheme`, such as an engine linking a
    ;; program's modules, needs: a compiled module, its imports, and a link
    ;; against providers it chooses, one per import.
    (record Compiled
      ((handle I32)))

    ;; The module `bytes` hold, or none when they are not one.

    (define (compile-bytes (wasm Wasm) (bytes Bytes)) (→ (Option Compiled)) (! mut)
      (let ((handle (compile wasm bytes)))
        (if (< handle 0) (None) (Some (new Compiled (handle handle))))))

    (enum ImportKind
      (FunctionImport)
      (TableImport)
      (MemoryImport)
      (GlobalImport))

    ;; An import: the module and field it names, and what it must be.
    (record Import
      ((from String)
       (name String)
       (kind ImportKind)))

    (define (module-imports (wasm Wasm) (compiled Compiled)) (→ (List Import)) (! mut)
      (map (lambda (index) (import-of wasm (● compiled handle) (i64->i32 index)))
           (iota (i32->i64 (import-count wasm (● compiled handle))))))

    (define (import-of (wasm Wasm) (module I32) (index I32)) (→ Import) (! mut)
      (let ((kind (import-at wasm module index)))
        (new Import (from (held-string wasm 0)) (name (held-string wasm 1)) (kind (kind-of kind)))))

    (define (kind-of (code I32)) (→ ImportKind)
      (cond ((= code 0) (FunctionImport))
            ((= code 1) (TableImport))
            ((= code 2) (MemoryImport))
            ((= code 3) (GlobalImport))
            (else (panic "the host answered an unknown kind of import"))))

    ;; A name the host holds, a character at a time.

    (define (held-string (wasm Wasm) (which I32)) (→ String) (! mut)
      (string-generate (i32->i64 (held-length wasm which))
                       (lambda (index) (held-char wasm which (i64->i32 index)))))

    ;; What provides an import: an export of an instance, the host's own
    ;; function of the import's module and field, that function when the
    ;; host has one and otherwise nothing, a function of no arguments
    ;; answering a constant, as a linked file's handle is imported, or
    ;; nothing, a function that fails if called, as a host import a program
    ;; never calls links. A provider that is not found, an export the
    ;; instance lacks or a function the host lacks, provides nothing, and
    ;; the link fails unless another is given for the import.
    (enum Provider
      (ExportOf
       ((instance Module)
        (export String)))
      (HostProvided)
      (HostIfProvided)
      (ConstantOf
       ((value I32)))
      (Unprovided))

    ;; The program that loads, as an instance whose exports a loaded module
    ;; may import.

    (define loading-program (→ Module) (new Module (handle 0)))

    ;; Links `compiled`, called `name` in a failure, with `providers`, one
    ;; per import in import order, and initializes it when it exports
    ;; `_initialize`. The link fails when a provider names no export, the
    ;; host has no such function, an import is left without a provider, or
    ;; a provider is not of the import's type; a trap while the module
    ;; starts still ends the program.

    (define (link-module (wasm Wasm) (name String) (compiled Compiled) (providers (List Provider)))
      (→ (Result Module LoadError))
      (! mut)
      (prepare-link wasm (● compiled handle))
      (for-each (lambda (provider) (provide wasm provider)) providers)
      (let ((handle (link-prepared wasm)))
        (if (< handle 0) (Err (LinkFailed name)) (Ok (new Module (handle handle))))))

    (define (provide (wasm Wasm) (provider Provider)) (→ Unit) (! mut)
      (match provider
        ((ExportOf instance export)
         (send-argument wasm export)
         (provide-export wasm (● instance handle))
         (unit))
        ((HostProvided) (provide-host wasm) (unit))
        ((HostIfProvided) (unless (provide-host wasm) (provide-missing wasm)))
        ((ConstantOf value) (provide-constant wasm value))
        ((Unprovided) (provide-missing wasm))))

    ;; Bind the program's runtime for staging bytes and reporting errors.
    ;; Handle zero continues to identify the loader, whose own runtime stays
    ;; separate from the program it runs.
    (define (bind-runtime (wasm Wasm) (runtime Module)) (→ Unit) (! mut)
      (runtime-instance wasm (● runtime handle)))

    ;; Calls the function the instance exports as `name`, of no argument or
    ;; one I64, such as its `main` or a scheduler's `tasks:turn`, with
    ;; `argument`, answering its result, or 0 when it answers nothing.

    (define (run-export (wasm Wasm) (instance Module) (name String) (argument I64))
      (→ (Result I64 LoadError))
      (! mut)
      (send-argument wasm name)
      (if (exports-function? wasm (● instance handle))
          (begin (send-argument wasm name) (Ok (call-export wasm (● instance handle) argument)))
          (Err (MissingExport name))))

    ))
