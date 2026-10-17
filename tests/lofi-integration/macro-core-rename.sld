(import (lofi primitive) (rename (only (lofi core) lambda if) (lambda fn) (if choose)))
((fn (x) (choose #t x 0)) 42)
