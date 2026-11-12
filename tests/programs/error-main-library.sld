;; (main) is the program's own name, so no library can be imported by it.
;; The old compiler once gave this library and the program one key and
;; one body: it ran the program's statement twice and the library's never,
;; and a name defined in both failed as a duplicate Wasm global.
(import
 (snail core base)
 (snail core io)
 (main))
(define from-program 2)
(write-line (show (+ from-library from-program)))
