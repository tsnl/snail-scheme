(import
  (scheme base)
  (snail-scheme common)
  (snail-scheme test-cli)
  (snail-scheme test-reader)
  (snail-scheme test-parser)
  (snail-scheme test-syntax))

(test-cli)
(test-reader)
(test-parser)
(test-syntax)
(display-error "All tests ok\n")
