(import (lofi core))
(def again (syntax-rules () ((_) (library-begin (again)))))
(again)
