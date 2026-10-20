;; The compiler's passes in order, from a program's source path to WebAssembly
;; text. Each pass's output is the next pass's only input. Both hosts run it:
;; Chibi through (lofi build), and the compiled compiler through
;; bootstrap/compile.sld.
(define-library (lofi compiler)
  (export
   compile->wat)
  (import
   (lofi base)
   (lofi io)
   (lofi compiler read)
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

    ))
