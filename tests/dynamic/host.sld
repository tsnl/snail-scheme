;; Loads what the plugin's build holds while this program runs. Its
;; argument is the module of the plugin's library (cell), which this
;; program does not import; the function it exports under its global name
;; is a Snail-Core function, cast to its type and called.
(import
 (snail-core base)
 (snail-core io)
 (snail-core wasm))

(: run-cell (-> String Unit ! wasm fs console))
(define (run-cell file)
  (match (load-module "cell" file)
    ((Ok cell)
     (match (module-export cell "cell:run")
       ((Ok function) (display ((ann (unsafe-cast function) (-> I64 I64)) 41)) (newline))
       ((Err error) (write-line (load-error-message error)))))
    ((Err error) (write-line (load-error-message error)))))

(match (command-line)
  ((Cons _ (Cons cell (Nil))) (run-cell cell))
  (_ (panic "usage: host CELL-MODULE")))
