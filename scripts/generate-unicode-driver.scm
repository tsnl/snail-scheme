(import
 (scheme base)
 (scheme process-context)
 (lofi tools generate-unicode))
(exit (generate-unicode-main (cadr (command-line)) (cddr (command-line))))
