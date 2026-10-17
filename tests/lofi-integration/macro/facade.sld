(define-library (macro facade)
  (import (rename (only (macro provider) add-one recognize marker) (add-one increment)))
  (export increment recognize marker))
