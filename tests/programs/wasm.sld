(import
 (snail-core base)
 (snail-core io)
 (snail-core wasm))

;; A module loaded while the program runs, and the function it exports
;; called at the type the program expects. The program writes the module
;; itself: each of its bytes is below 128, so its text is its binary. Its
;; function takes the evidence first, as a Snail-Core function does.
;;   (module
;;     (type $evidence (struct (field i32) (field (ref null any)) (field (mut (ref null $evidence)))))
;;     (func (export "add") (param (ref $evidence) i64 i64) (result i64)
;;       (i64.add (local.get 1) (local.get 2))))
(: adder (List I32))
(define adder
  (list 0 97 115 109 1 0 0 0
        1 19 2 95 3 127 0 99 110 0 99 0 1 96 3 100 0 126 126 1 126
        3 2 1 1
        7 7 1 3 97 100 100 0 0
        10 9 1 7 0 32 1 32 2 124 11))

(define path "build/tests/adder.wasm")
(write-file path (list->string (map i32->char adder)))
(let* ((module (load-module "adder" path))
       (add (ann (unsafe-cast (module-export module "add")) (-> I64 I64 I64))))
  (display (add 40 2))
  (newline)
  (display (fold-left (lambda (total n) (add total n)) 0 (list 1 2 3)))
  (newline))
