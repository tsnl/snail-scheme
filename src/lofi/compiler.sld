;; The compiler's passes in order, from a program's source path to WebAssembly
;; text, or to the schemas of its wire types. Each pass's output is the next pass's only input. Both hosts run it:
;; Chibi through (lofi build), and the compiled compiler through
;; bootstrap/compile.sld.
(define-library (lofi compiler)
  (export
   compile->wat
   compile->modules
   compile->schemas)
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
    (: compile->wat (-> (List String) String (-> (List Syntax) Bytes ! mut fs) String ! mut fs))
    (define (compile->wat directories source generate)
      (wat->string (emit-module (monomorphize (check-program (ExpandedProgram-program (expand-program directories generate source (None))))))))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from. This is a
    ;; session's build with nothing kept from before.
    (: compile->modules (-> (List String) String (-> (List Syntax) Bytes ! mut fs) (List (Pair String String)) ! mut fs))
    (define (compile->modules directories source generate)
      (map (lambda (built) (Pair (Built-name built) (Built-text built))) (Pair-first (build-session (make-session directories generate) source))))

    (: compile->schemas (-> (List String) String (-> (List Syntax) Bytes ! mut fs) String ! mut fs))
    (define (compile->schemas directories source generate)
      (wire-schemas (Typed-program (check-program (ExpandedProgram-program (expand-program directories generate source (None)))))))

    ))
