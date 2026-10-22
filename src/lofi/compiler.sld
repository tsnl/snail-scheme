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
   (lofi compiler wasm))
  (begin

    ;; `generate` runs the producer program of a `generate-library` and
    ;; returns what it prints.
    (: compile->wat (-> (List String) String (-> (List Syntax) String String ! mut fs) String ! mut fs))
    (define (compile->wat directories source generate)
      (wat->string (emit-module (monomorphize (check-program (expand-program (make-context directories generate) source))))))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from.
    (: compile->modules (-> (List String) String (-> (List Syntax) String String ! mut fs) (List (Pair String String)) ! mut fs))
    (define (compile->modules directories source generate)
      (let ((typed (check-program (expand-program (make-context directories generate) source))))
        (map (lambda (unit)
               (let ((owner (Pair-first unit)))
                 (Pair owner (wat->string (emit-unit (monomorphize-unit typed owner (Pair-second unit)) owner)))))
             (unit-items (Typed-program typed) (Typed-items typed)))))

    (: compile->schemas (-> (List String) String (-> (List Syntax) String String ! mut fs) String ! mut fs))
    (define (compile->schemas directories source generate)
      (wire-schemas (Typed-program (check-program (expand-program (make-context directories generate) source)))))

    ))
