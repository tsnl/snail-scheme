(import (lofi primitive) (rename (macro facade) (marker renamed)))
(let private-step (lambda (value) 777))
(let helper (lambda (x) 999))
(i32-add (increment 1) (recognize renamed))
