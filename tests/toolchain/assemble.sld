;; The toolchain's in-process assembler, (snail shell assembler), from a
;; tool linked with the toolchain's runtime:
;;
;;   assemble PROGRAM.wat MODULE.wasm
;;
;; assembles the compiler's text for a program into MODULE.wasm, which the
;; test then runs, and shows that broken text fails naming its line and
;; column.
(import
 (snail core base)
 (snail core io)
 (snail shell assembler))

(: contains? (-> String String Bool))
(define (contains? text part)
  (let loop ((start 0))
    (cond ((> (+ start (string-length part)) (string-length text)) #f)
          ((string=? (substring text start (+ start (string-length part))) part) #t)
          (else (loop (+ start 1))))))

(match (command-line)
  ((Cons _ (Cons text (Cons module (Nil))))
   (match (assemble (read-file text))
     ((Ok bytes)
      (write-bytes module bytes)
      (write-line "assembled the program"))
     ((Err message) (write-line message))))
  (_ (panic "usage: assemble PROGRAM.wat MODULE.wasm")))

(match (assemble "(module\n  (func (result i32) (i32.bogus)))")
  ((Ok _) (write-line "assembled broken text"))
  ((Err message)
   (write-line (if (contains? message ":2:23")
                   "broken text names its line and column"
                   message))))
