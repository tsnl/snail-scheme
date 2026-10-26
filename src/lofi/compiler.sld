;; The compiler's passes in order, from a program's source path to
;; WebAssembly text, or to the schemas of its wire types. In a one-off
;; compile each pass's output is the next pass's only input; a session,
;; (lofi compiler session), also keeps what each library became in the
;; build before. The typed driver serves both compiler entries: Chibi runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (lofi compiler)
  (export
   compile->wat
   compile->modules
   compile->schemas
   no-artifacts)
  (import
   (lofi base)
   (lofi io)
   (lofi compiler read)
   (lofi compiler core)
   (lofi compiler expand)
   (lofi compiler check)
   (lofi compiler mono)
   (lofi compiler wasm)
   (lofi compiler session))
  (begin

    ;; `generate` runs the producer program of a `generate-library` and
    ;; returns the bytes of the syntax it writes.
    (: compile->wat (-> (List String) String (-> (List Syntax) Bytes ! mut fs) ArtifactInputs String ! mut fs))
    (define (compile->wat directories source generate artifacts)
      (wat->string (emit-module (monomorphize (check-program (ExpandedProgram-program (expand-program directories generate artifacts source empty-expansion)))))))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from. This is a
    ;; session's build with nothing kept from before.
    (: compile->modules (-> (List String) String (-> (List Syntax) Bytes ! mut fs) ArtifactInputs (List (Pair String String)) ! mut fs))
    (define (compile->modules directories source generate artifacts)
      (map (lambda (built) (Pair (Built-name built) (Built-text built))) (Pair-first (build-session (make-session directories generate) source artifacts))))

    (: compile->schemas (-> (List String) String (-> (List Syntax) Bytes ! mut fs) ArtifactInputs String ! mut fs))
    (define (compile->schemas directories source generate artifacts)
      (wire-schemas (Typed-program (check-program (ExpandedProgram-program (expand-program directories generate artifacts source empty-expansion))))))

    ))
