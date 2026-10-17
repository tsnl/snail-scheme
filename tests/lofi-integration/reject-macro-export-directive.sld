(import (lofi core))
(def expose (syntax-rules () ((_) (library-begin (export)))))
(expose)
42
