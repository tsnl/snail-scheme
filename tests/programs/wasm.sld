(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

;; Link a module from bytes and call its export through an Fn closure.
;; Its function takes evidence first, as a Snail Scheme function does.
;; The bytes encode the nullable internal reference ABI. Evidence
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
        99
        3
        99
        3
        99
        3
        1
        99
        3
        80
        0
        95
        2
        126
        1
        99
        2
        0
        96
        2
        99
        1
        99
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
        99
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
        99
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

(define (use-adder (module Module)) (→ Unit) (! wasm output-port)
  (match (module-export module "add")
    ((Ok function)
     (let ((add (ann (unsafe-cast function) (Fn I64 I64 → I64))))
       (display (add 40 2))
       (newline)
       (display (fold-left (lambda (total n) (add total n)) 0 (list 1 2 3)))
       (newline)))
    ((Err error) (write-line (load-error-message error)))))

;; A module importing the runtime's memory as a function fails to link.
;;   (module (import "snail.core.support" "memory" (func)))
(define mislinked (→ (List I32))
  (list 0 97 115 109 1 0 0 0
        1 4 1 96 0 0
        2 29 1 18 115 110 97 105 108 46 99 111 114 101 46 115 117 112 112 111 114 116
        6 109 101 109 111 114 121 0 0))

(define (main) (→ Unit) (! output-port wasm)
  (let ((adder (compiled adder)) (mislinked (compiled mislinked)))
    (match (link-module "adder" adder (Nil))
      ((Ok module)
       (use-adder module)
       (match (module-export module "subtract")
         ((Ok _) (write-line "subtract is exported"))
         ((Err error) (write-line (load-error-message error)))))
      ((Err error) (write-line (load-error-message error))))
    (match (link-module "mislinked" mislinked (list (ExportOf loading-program "memory")))
      ((Ok _) (write-line "linked incompatible import"))
      ((Err error) (write-line (load-error-message error)))))
  (unit))

(define (compiled (bytes (List I32))) (→ Compiled) (! wasm)
  (match (compile-bytes (list->vector (map i32->u8 bytes)))
    ((Some module) module)
    ((None) (panic "invalid fixture binary"))))
