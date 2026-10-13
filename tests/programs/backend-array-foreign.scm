(import (scheme base) (scheme write) (snail unsafe)
        (only (snail-scheme extensions) array-boundaries))
(define numeric (array.new storage.f64 2 1.25))
(define boxed (array.new storage.eqref 2 #f))
(array-boundaries numeric boxed storage.f64 storage.eqref
                  (inst array.ref Eqref) (inst array.append Eqref) (inst array.copy! Eqref)
                  (lambda (destination source) (vector-copy! destination 0 source)))
(display "foreign array checks passed\n")
