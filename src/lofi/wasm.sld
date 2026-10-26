;; Loading WebAssembly while a program runs, as C loads a shared library
;; with dlopen and finds a function in it with dlsym. A module is loaded
;; from a file and linked against the program's own modules, the runtime,
;; and the modules loaded before it, by name, so a module can import one
;; loaded earlier. Its exported
;; functions come out as Funcref values, untyped; `unsafe-cast` makes one a
;; function of the type the program expects. Nothing checks that type: the
;; engine traps only if the function's WebAssembly type differs from the one
;; Lofi gives the expected type. A program compiled one library at a time
;; exports each function under its library's name and its own, as in
;; `cell:run`.
(define-library (lofi wasm)
  (export
   Funcref
   Module
   load-module
   module-export
   unsafe-cast
   wasm)
  (import
   (lofi base)
   (only (lofi core) Funcref)
   (only (lofi primitive) unsafe-cast))
  (begin

    ;; ---- Host operations ----

    ;; Each operation takes string arguments a character at a time; the host
    ;; reads a file's bytes as its own file system holds them.
    (effect wasm
      ((argument-character (-> Char Unit))
       (argument-end (-> Unit))
       (load (-> I32))
       (export-function (-> I32 Funcref)))
      (host "snail.wasm"
            ((argument-character "argument-character")
             (argument-end "argument-end")
             (load "load")
             (export-function "export-function"))))

    (: send-argument (-> String Unit ! wasm))
    (define (send-argument text)
      (let loop ((index 0))
        (when (< index (string-length text))
          (argument-character (string-ref text index))
          (loop (+ index 1))))
      (argument-end))

    ;; ---- Modules ----

    (struct Module
      ((handle I32)))

    ;; Loads the module in `file` under the library name `name`. Linking
    ;; fails, ending the program, if an import has no provider.
    (: load-module (-> String String Module ! wasm))
    (define (load-module name file)
      (send-argument name)
      (send-argument file)
      (Module (load)))

    ;; The function the module exports as `name`; there must be one.
    (: module-export (-> Module String Funcref ! wasm))
    (define (module-export module name)
      (send-argument name)
      (export-function (Module-handle module)))))
