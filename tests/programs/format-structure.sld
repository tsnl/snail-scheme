;; Structural layout before the Emacs-compatible indentation/width pass.
;; Check its output, idempotence and the reader's resulting data.
(import
 (snail core base)
 (snail core io)
 (snail shell format)
 (only (snail shell compiler read) read-text syntax->string compiling Stop))

(: source String)
(define source
  "(define (choose x) (let ((a 1) (b 2)) (if x (+ a b) 0)))\n(let loop ((n 3) (acc 0)) (if (= n 0) acc (loop (- n 1) (+ acc n))))\n(match value ((Some x) (show x)) ((None) \"none\"))\n(cond ((> x 0) x) (else 0))\n(begin (write \"a\") (write \"b\"))\n(when ready (run) (finish))\n(define data '(if x a b))\n#;(define (ignored x) (if x a b))\n(define (commented x) ; keep this comment\n  (let ((a \"(if x a b)\") #| keep |# (b #\\()) (if x a b)))\n(import (rename (a) (if old-if)))\n(: f (-> I64 I64 ! console))\n(define (bytes x) #u8(1 2) (if x ' #u8(3) #u8(4)))\n( if x a b)\n(\nif x a b)\n(if #;ignored condition a b)\n(#;ignored if x a b)\n(if #;#;one two condition a b)\n(let\nloop ((a 1) (b 2)) (if a b 0))\n(let #|comment|# loop ((a 1) (b 2)) (if a b 0))\n(if (let ((a 1) (b 2)) (if a b 0)) x y)\n(cond ((if x #t #f) a) (else b))\n(let-values (((if x y) (values 1 2 3))) (if x y 0))\n")

(: reading (-> String (Result (List String) Stop)))
(define (reading text)
  (compiling (lambda () (map syntax->string (read-text text "format.sld")))))

(define formatted (format-structure source 80))
(unless (string=? formatted (format-structure formatted 80)) (panic "not idempotent"))
(match (Pair (reading source) (reading formatted))
  ((Pair (Ok before) (Ok after))
   (unless (string=? (string-join before "\n") (string-join after "\n"))
     (panic "changed reader data")))
  (_ (panic "formatting broke syntax")))
(write-string formatted)

;; The formatter also accepts Scheme reader prefixes beyond Snail-Core's
;; source reader. Keep vectors and quasiquotes intact, including whitespace
;; after quote marks, and preserve incomplete editor input.
(: check-layout (-> String String Unit))
(define (check-layout source expected)
  (let ((result (format-structure source 80)))
    (unless (and (string=? result expected)
                 (string=? result (format-structure result 80)))
      (panic (string-append "unexpected layout: " result)))))

(check-layout "(define data #(1 2))" "(define data\n  #(1 2))")
(check-layout "(define data `((if x a b) ,value ,@values))"
              "(define data\n  `((if x a b) ,value ,@values))")
(check-layout "(begin \"a\nb\" (run) (finish))"
              "(begin\n  \"a\nb\"\n  (run)\n  (finish))")
(check-layout "(define (f x) (if x (f x)" "(define (f x)\n  (if x\n      (f x)")
(write-line "reader prefixes, multiline literals and incomplete input")
