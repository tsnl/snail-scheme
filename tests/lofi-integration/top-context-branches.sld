(import (lofi primitive))

(def Choice (datatype () (some) (none)))
(def branch (ann (if #t 40 #f) Any))
(def matched (ann (match (some) ((some) 2) ((none) #f)) Any))

(i32-add (ann branch I32) (ann matched I32))
