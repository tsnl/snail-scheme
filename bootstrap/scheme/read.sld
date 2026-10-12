;; Native datum input over the same cursor as the character input procedures.
(define-library (scheme read)
  (export read)
  (import (only (snail-scheme core) read)))
