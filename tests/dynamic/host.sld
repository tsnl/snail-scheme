;; Loads what the plugin's build holds while this program runs. Its
;; argument is the module of the plugin's library (cell), which this
;; program does not import; the function it exports under its global name
;; is a Snail-Core function, cast to its type and called.
(import
 (snail-core base)
 (snail-core io)
 (snail-core wasm))

(match (command-line)
  ((Cons _ (Cons cell-file (Nil)))
   (let* ((cell (load-module "cell" cell-file))
          (run (ann (unsafe-cast (module-export cell "cell:run")) (-> I64 I64))))
     (display (run 41))
     (newline)))
  (_ (panic "usage: host CELL-MODULE")))
