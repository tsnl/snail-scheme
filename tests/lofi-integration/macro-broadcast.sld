(import (lofi primitive))
(def sum (syntax-rules () ((_) 0) ((_ x rest ...) (i32-add x (sum rest ...)))))
(def add-shared (syntax-rules () ((_ shared (x ...)) (sum (i32-add shared x) ...))))
(add-shared 10 (1 9 2))
