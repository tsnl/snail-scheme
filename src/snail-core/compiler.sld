;; The compiler's passes in order, from a program's source path to
;; WebAssembly text, or to the schemas of its wire types. In a one-off
;; compile each pass's output is the next pass's only input; a session,
;; (snail-core compiler session), also keeps what each library became in the
;; build before. The typed driver serves both compiler entries: Chibi runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (snail-core compiler)
  (export
   check-source
   compile->wat
   compile->modules
   compile->schemas
   no-artifacts)
  (import
   (snail-core base)
   (snail-core io)
   (snail-core compiler read)
   (snail-core compiler core)
   (snail-core compiler expand)
   (snail-core compiler check)
   (snail-core compiler mono)
   (snail-core compiler wasm)
   (snail-core compiler session))
  (begin

    ;; Specialization also proves concrete handler captures and affine uses.
    ;; Checking stops before emission, retaining no backend result.
    (: check-source (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) ArtifactInputs Unit ! mut fs))
    (define (check-source directories source generate artifacts)
      (monomorphize (check-program (ExpandedProgram-program (expand-program directories generate artifacts source empty-expansion))))
      (unit))

    ;; `generate` runs the producer program of a `generate-library`, given
    ;; the libraries loading when it was reached, and returns the bytes of
    ;; the syntax it writes.
    (: compile->wat (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) ArtifactInputs String ! mut fs))
    (define (compile->wat directories source generate artifacts)
      (wat->string (emit-module (monomorphize (check-program (ExpandedProgram-program (expand-program directories generate artifacts source empty-expansion)))))))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from. This is a
    ;; session's build with nothing kept from before.
    (: compile->modules (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) ArtifactInputs (List (Pair String String)) ! mut fs))
    (define (compile->modules directories source generate artifacts)
      (map (lambda (built) (Pair (Built-name built) (Built-text built))) (Pair-first (build-session (make-session directories) source generate artifacts))))

    (: compile->schemas (-> (List String) String (-> (List String) (List Syntax) Bytes ! mut fs) ArtifactInputs String ! mut fs))
    (define (compile->schemas directories source generate artifacts)
      (wire-schemas (Typed-program (check-program (ExpandedProgram-program (expand-program directories generate artifacts source empty-expansion))))))

    ))
