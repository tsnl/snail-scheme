(import
 (lofi base)
 (lofi io)
 (lofi wasm))

;; A module loaded while the program runs, and the function it exports
;; called at the type the program expects. The program writes the module
;; itself: each of its bytes is below 128, so its text is its binary.
;;   (module (func (export "add") (param i64 i64) (result i64)
;;             (i64.add (local.get 0) (local.get 1))))
(: adder (List I32))
(define adder
  (list 0 97 115 109 1 0 0 0
        1 7 1 96 2 126 126 1 126
        3 2 1 0
        7 7 1 3 97 100 100 0 0
        10 9 1 7 0 32 0 32 1 124 11))

(define path "build/tests/adder.wasm")
(write-file path (list->string (map i32->char adder)))
(let* ((module (load-module "adder" path))
       (add (ann (unsafe-cast (module-export module "add")) (-> I64 I64 I64))))
  (display (add 40 2))
  (newline)
  (display (fold-left (lambda (total n) (add total n)) 0 (list 1 2 3)))
  (newline))
