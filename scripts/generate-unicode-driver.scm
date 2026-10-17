(import
 (scheme base)
 (scheme process-context)
 (lofi compiler tools generate-unicode))
(exit (generate-unicode-main (cadr (command-line)) (cddr (command-line))))
