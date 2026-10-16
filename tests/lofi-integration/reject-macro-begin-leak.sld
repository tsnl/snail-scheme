(import (lofi core))
(def local (syntax-rules () ((_ name) (begin (def name 42) name))))
(local hidden)
hidden
