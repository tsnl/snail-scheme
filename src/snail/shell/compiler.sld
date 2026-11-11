;; The compiler's passes in order, from a program's source path to
;; WebAssembly text, or to the schemas of its wire types. In a one-off
;; compile each pass's output is the next pass's only input; a session,
;; (snail shell compiler session), also keeps what each library became in the
;; build before. The typed driver serves both compiler entries: Chibi runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (snail shell compiler)
  (export
   WholeProgram
   source->wat
   source->modules
   source->schemas
   Built
   LinkedFile
   no-inputs)
  (import
   (snail core base)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler inputs) Inputs)
   (snail shell compiler core)
   (snail shell compiler expand)
   (snail shell compiler check)
   (snail shell compiler prepare)
   (snail shell compiler wasm)
   (snail shell compiler session))
  (begin

    ;; The front of every compile: the program a source path reads, expanded.
    ;; `generate` runs the producer program of a `generate-library`, given
    ;; the libraries loading when it was reached, and returns the bytes of
    ;; the syntax it writes.

    (define (source->expanded (directories (List String))
                              (source String)
                              (generate (dyn (Fn (List String) (List Syntax) → Bytes ! fs compile)))
                              (inputs Inputs))
      (→ ExpandedProgram)
      (! fs compile)
      (expand-program directories generate inputs source empty-expansion))

    ;; A program compiled to one module: its text, and the files it links,
    ;; which ship beside it.
    (struct WholeProgram
      ((text String)
       (links (List LinkedFile))))

    (define (source->wat (directories (List String))
                         (source String)
                         (generate (dyn (Fn (List String) (List Syntax) → Bytes ! fs compile)))
                         (inputs Inputs))
      (→ WholeProgram)
      (! mut fs compile)
      (let* ((expanded (source->expanded directories source generate inputs))
             (typed (check-program (::program expanded)))
             (module (emit-module (prepare-program typed))))
        (WholeProgram (wat->string module) (program-links expanded))))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from, with the files
    ;; its library links. This is a session's build with nothing kept from
    ;; before.

    (define (source->modules (directories (List String))
                             (source String)
                             (generate (dyn (Fn (List String) (List Syntax) → Bytes ! fs compile)))
                             (inputs Inputs))
      (→ (List Built))
      (! mut fs compile)
      (::first (build-session (make-session directories) source generate inputs)))

    (define (source->schemas (directories (List String))
                             (source String)
                             (generate (dyn (Fn (List String) (List Syntax) → Bytes ! fs compile)))
                             (inputs Inputs))
      (→ String)
      (! fs compile)
      (let ((typed (check-program (::program
                                   (source->expanded directories source generate inputs)))))
        (wire-schemas (::program typed))))

    ))
