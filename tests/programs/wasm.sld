(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

;; Link a module from bytes and call its export through an Fn closure.
;; The only function is (param i64 i64) -> i64, the type a `snail-scheme`
;; function of two I64s to an I64 has, and adds its two locals.
(define (adder) (→ (List I32))
  (list 0 97 115 109 1 0 0 0
        ;; The type section: one function type.
        1 7 1 96 2 126 126 1 126
        ;; One function, of that type.
        3 2 1 0
        ;; Exported as "add".
        7 7 1 3 97 100 100 0 0
        ;; Its code: local.get 0, local.get 1, i64.add.
        10 9 1 7 0 32 0 32 1 124 11))

(define (use-adder (wasm Wasm) (out OutputPort) (module Module)) (→ Unit)
  (match (module-export wasm module "add")
    ((Ok function)
     (let ((add (ann (unsafe-cast function) (Fn I64 I64 → I64))))
       (display out (add 40 2))
       (newline out)
       (display out (fold-left (lambda (total n) (add total n)) 0 (list 1 2 3)))
       (newline out)))
    ((Err error) (write-line out (load-error-message error)))))

;; A module importing the runtime's memory as a function fails to link.
;;   (module (import "snail.core.support" "memory" (func)))
(define (mislinked) (→ (List I32))
  (list 0 97 115 109 1 0 0 0
        1 4 1 96 0 0
        2 29 1 18 115 110 97 105 108 46 99 111 114 101 46 115 117 112 112 111 114 116
        6 109 101 109 111 114 121 0 0))

(define (main (wasm Wasm) (out OutputPort)) (→ Unit)
  (let ((adder (compiled wasm (adder))) (mislinked (compiled wasm (mislinked))))
    (match (link-module wasm "adder" adder (Nil))
      ((Ok module)
       (use-adder wasm out module)
       (match (module-export wasm module "subtract")
         ((Ok _) (write-line out "subtract is exported"))
         ((Err error) (write-line out (load-error-message error)))))
      ((Err error) (write-line out (load-error-message error))))
    (match (link-module wasm "mislinked" mislinked (list (ExportOf loading-program "memory")))
      ((Ok _) (write-line out "linked incompatible import"))
      ((Err error) (write-line out (load-error-message error)))))
  (unit))

(define (compiled (wasm Wasm) (bytes (List I32))) (→ Compiled)
  (match (compile-bytes wasm (list->array (map i32->u8 bytes)))
    ((Some module) module)
    ((None) (panic "invalid fixture binary"))))
