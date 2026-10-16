;; Cargo's selected compiler and exact argument vector enter unchanged.
(import (scheme base) (wasm-native process) (wasm-native native-build))
(command-line-main
 (lambda (arguments)
   (unless (pair? arguments) (error "missing compiler wrapper root"))
   (native-rustc-main (car arguments) (cdr arguments))))
