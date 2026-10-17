(import (lofi core) (only (macro declarations) application))
(def State (datatype () (state (value I32))))
(def Other (datatype () (other (value I32))))
(application commands State (lambda (current) current) (lambda (current) (other 42)))
42
