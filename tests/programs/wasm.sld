(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

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

(: use-adder (-> Module Unit ! wasm console))
(define (use-adder module)
  (match (module-export module "add")
    ((Ok function)
     (let ((add (ann (unsafe-cast function) (-> I64 I64 I64))))
       (display (add 40 2))
       (newline)
       (display (fold-left (lambda (total n) (add total n)) 0 (list 1 2 3)))
       (newline)))
    ((Err error) (write-line (load-error-message error)))))

(match (load-module "adder" path)
  ((Ok module)
   (use-adder module)
   (match (module-export module "subtract")
     ((Ok _) (write-line "subtract is exported"))
     ((Err error) (write-line (load-error-message error)))))
  ((Err error) (write-line (load-error-message error))))

;; Failures are values: a name linked already, a file that is missing, one
;; that is not a module, and a module that imports the runtime's memory as
;; a function.
;;   (module (import "snail.core.support" "memory" (func)))
(: mislinked (List I32))
(define mislinked
  (list 0 97 115 109 1 0 0 0
        1 4 1 96 0 0
        2 29 1 18 115 110 97 105 108 46 99 111 114 101 46 115 117 112 112 111 114 116
        6 109 101 109 111 114 121 0 0))

(define text-path "build/tests/adder.txt")
(write-file text-path "not a module")
(define mislinked-path "build/tests/mislinked.wasm")
(write-file mislinked-path (list->string (map i32->char mislinked)))
(for-each (lambda (entry)
            (match (load-module (Pair-first entry) (Pair-second entry))
              ((Ok _) (write-line "loaded"))
              ((Err error) (write-line (load-error-message error)))))
          (list (Pair "adder" path)
                (Pair "missing" "build/tests/missing.wasm")
                (Pair "text" text-path)
                (Pair "mislinked" mislinked-path)))
