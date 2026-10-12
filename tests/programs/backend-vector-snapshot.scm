(import (scheme base) (scheme write)
        (only (snail-scheme extensions) snapshot-input snapshot-mutate!))

;; The host returns a vector whose second element is a mutable values envelope.
;; Its first callback mutates that envelope and any nested envelope independently.
(write (vector-map (lambda (value) (display value) (snapshot-mutate!) value) (snapshot-input)))
(newline)
