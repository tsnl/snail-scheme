(import (lofi primitive))
(def bad (syntax-rules () ((_ value) (i32-add value #t))))
(bad 1)
