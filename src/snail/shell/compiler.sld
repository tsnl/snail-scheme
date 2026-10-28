;; The compiler's passes in order, from a program's source path to
;; WebAssembly text, or to the schemas of its wire types. In a one-off
;; compile each pass's output is the next pass's only input; a session,
;; (snail shell compiler session), also keeps what each library became in the
;; build before. The typed driver serves both compiler entries: Chibi runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (snail shell compiler)
  (export
   WholeProgram
   WholeProgram-text
   WholeProgram-links
   source->wat
   source->modules
   source->schemas
   Built
   Built-name
   Built-text
   Built-links
   LinkedFile
   LinkedFile-name
   LinkedFile-path
   no-inputs)
  (import
   (snail core base)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler inputs) Inputs)
   (snail shell compiler core)
   (snail shell compiler expand)
   (snail shell compiler check)
   (snail shell compiler mono)
   (snail shell compiler control)
   (snail shell compiler wasm)
   (snail shell compiler session))
  (begin

    ;; The front of every compile: the program a source path reads, expanded.
    ;; `generate` runs the producer program of a `generate-library`, given
    ;; the libraries loading when it was reached, and returns the bytes of
    ;; the syntax it writes.
    (: source->expanded
       (-> (List String)
           String
           (-> (List String) (List Syntax) Bytes ! fs)
           Inputs
           ExpandedProgram
           ! fs))
    (define (source->expanded directories source generate inputs)
      (expand-program directories generate inputs source empty-expansion))

    ;; A program compiled to one module: its text, and the files it links,
    ;; which ship beside it.
    (struct WholeProgram
      ((text String)
       (links (List LinkedFile))))

    (: source->wat
       (-> (List String)
           String
           (-> (List String) (List Syntax) Bytes ! fs)
           Inputs
           WholeProgram
           ! mut fs))
    (define (source->wat directories source generate inputs)
      (let* ((expanded (source->expanded directories source generate inputs))
             (typed (check-program (ExpandedProgram-program expanded)))
             (mono (name-yield-points (monomorphize typed)))
             (module (emit-module mono)))
        (WholeProgram (wat->string module) (program-links expanded))))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from, with the files
    ;; its library links. This is a session's build with nothing kept from
    ;; before.
    (: source->modules
       (-> (List String)
           String
           (-> (List String) (List Syntax) Bytes ! fs)
           Inputs
           (List Built)
           ! mut fs))
    (define (source->modules directories source generate inputs)
      (Pair-first (build-session (make-session directories) source generate inputs)))

    (: source->schemas
       (-> (List String) String (-> (List String) (List Syntax) Bytes ! fs) Inputs String ! fs))
    (define (source->schemas directories source generate inputs)
      (let ((typed (check-program (ExpandedProgram-program
                                   (source->expanded directories source generate inputs)))))
        (wire-schemas (Typed-program typed))))

    ))
