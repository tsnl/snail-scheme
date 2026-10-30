;; The compiled compiler, an ordinary program: one compile, from its
;; command line, which exits with status 1 when the compile fails or needs
;; an input.
(import
 (snail core base)
 (snail core io)
 (snail shell compiler driver))

(compile-command-line)
