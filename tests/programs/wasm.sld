(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

;; A module loaded while the program runs, and the function it exports
;; called at the type the program expects: as a closure, or as an Fn,
;; which is the code itself. The program writes the module itself: each of
;; its bytes is below 128, so its text is its binary. Its function takes
;; the evidence first, as a Snail Scheme function does.
;; The bytes encode the current recursive owner/evidence ABI. Evidence
;; includes the owner header and the forwarding/copy links used by resumptions;
;; an older three-field evidence type is not interchangeable with this one.
;; The only function is (param evidence i64 i64) -> i64 and adds locals 1 and 2.
(define adder (→ (List I32))
  (list 0
        97
        115
        109
        1
        0
        0
        0
        1
        62
        2
        78
        4
        96
        3
        100
        3
        100
        3
        99
        3
        1
        100
        3
        80
        0
        95
        2
        126
        1
        100
        2
        0
        96
        2
        100
        1
        100
        3
        1
        127
        79
        1
        1
        95
        7
        126
        1
        100
        2
        0
        127
        0
        110
        0
        99
        3
        0
        99
        0
        0
        99
        3
        0
        96
        3
        100
        3
        126
        126
        1
        126
        3
        2
        1
        4
        7
        7
        1
        3
        97
        100
        100
        0
        0
        10
        9
        1
        7
        0
        32
        1
        32
        2
        124
        11))

(define path "build/tests/adder.wasm")

(define (use-adder (module Module)) (→ Unit) (! wasm output-port)
  (match (module-export module "add")
    ((Ok function)
     (let ((add (ann (unsafe-cast function) (Fn I64 I64 → I64)))
           (code (ann (unsafe-cast function) (fn I64 I64 → I64))))
       (display (add 40 2))
       (newline)
       (display (fold-left (lambda (total n) (add total n)) 0 (list 1 2 3)))
       (newline)
       (display (code 40 1))
       (newline)))
    ((Err error) (write-line (load-error-message error)))))

;; Failures are values: a name linked already, a file that is missing, one
;; that is not a module, and a module that imports the runtime's memory as
;; a function.
;;   (module (import "snail.core.support" "memory" (func)))
(define mislinked (→ (List I32))
  (list 0 97 115 109 1 0 0 0
        1 4 1 96 0 0
        2 29 1 18 115 110 97 105 108 46 99 111 114 101 46 115 117 112 112 111 114 116
        6 109 101 109 111 114 121 0 0))

(define text-path "build/tests/adder.txt")

(define mislinked-path "build/tests/mislinked.wasm")

(define (main) (→ Unit) (! fs output-port wasm)
  (write-file path (list->string (map i32->char adder)))
  (match (load-module "adder" path)
    ((Ok module)
     (use-adder module)
     (match (module-export module "subtract")
       ((Ok _) (write-line "subtract is exported"))
       ((Err error) (write-line (load-error-message error)))))
    ((Err error) (write-line (load-error-message error))))
  (write-file text-path "not a module")
  (write-file mislinked-path (list->string (map i32->char mislinked)))
  (for-each (lambda (entry)
              (match (load-module (● entry first) (● entry second))
                ((Ok _) (write-line "loaded"))
                ((Err error) (write-line (load-error-message error)))))
            (list (Pair "adder" path)
                  (Pair "missing" "build/tests/missing.wasm")
                  (Pair "text" text-path)
                  (Pair "mislinked" mislinked-path)))
  (unit))
