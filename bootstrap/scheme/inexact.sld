;; Real-number operations provided through the rooted Rust boundary.
(define-library (scheme inexact)
  (export acos asin atan cos exp finite? infinite? log nan? sin sqrt tan)
  (import (only (snail-scheme core)
                acos asin atan cos exp finite? infinite? log nan? sin sqrt tan)))
