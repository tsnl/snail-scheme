;; The harness keeps stdin open: reading one complete datum must not await EOF.
(import (scheme base) (scheme read) (scheme write))
(write (read))
(newline)
(flush-output-port)
