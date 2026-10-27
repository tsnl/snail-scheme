;; The compiler's passes in order, from a program's source path to
;; WebAssembly text, or to the schemas of its wire types. In a one-off
;; compile each pass's output is the next pass's only input; a session,
;; (snail-core compiler session), also keeps what each library became in the
;; build before. The typed driver serves both compiler entries: Chibi runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (snail-core compiler)
  (export
   source->wat
   source->modules
   source->schemas
   no-inputs)
  (import
   (snail-core base)
   (snail-core io)
   (snail-core compiler read)
   (only (snail-core compiler inputs) Inputs)
   (snail-core compiler core)
   (snail-core compiler expand)
   (snail-core compiler check)
   (snail-core compiler mono)
   (snail-core compiler wasm)
   (snail-core compiler session))
  (begin

    ;; The front of every compile: the program a source path reads, expanded
    ;; and type-checked. `generate` runs the producer program of a
    ;; `generate-library`, given the libraries loading when it was reached,
    ;; and returns the bytes of the syntax it writes.
    (: source->typed (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) Inputs Typed ! mut fs))
    (define (source->typed directories source generate inputs)
      (let* ((expanded (expand-program directories generate inputs source empty-expansion))
             (program (ExpandedProgram-program expanded)))
        (check-program program)))

    (: source->wat (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) Inputs String ! mut fs))
    (define (source->wat directories source generate inputs)
      (let* ((typed (source->typed directories source generate inputs))
             (mono (monomorphize typed))
             (module (emit-module mono)))
        (wat->string module)))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from. This is a
    ;; session's build with nothing kept from before.
    (: source->modules (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) Inputs (List (Pair String String)) ! mut fs))
    (define (source->modules directories source generate inputs)
      (let* ((built (build-session (make-session directories) source generate inputs))
             (modules (Pair-first built)))
        (map (lambda (module) (Pair (Built-name module) (Built-text module))) modules)))

    (: source->schemas (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) Inputs String ! mut fs))
    (define (source->schemas directories source generate inputs)
      (let ((typed (source->typed directories source generate inputs)))
        (wire-schemas (Typed-program typed))))

    ))
