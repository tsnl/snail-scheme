(import (scheme base) (snail-tools process) (snail-tools native-build))
(command-line-main (lambda (arguments) (build-native-main (car arguments) (cdr arguments))))
