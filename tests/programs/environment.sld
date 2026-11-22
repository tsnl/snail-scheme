(import
 (snail core base)
 (snail core io))

;; The environment and the working directory, as total reads. The suite runs
;; with PATH set; the host's own channel for the working directory is hidden.
(define (set? (name String)) (→ String)
  (match (environment-variable name)
    ((Some value) (if (string=? value "") "set, empty" "set"))
    ((None) "unset")))

(define (main (fs Fs) (out OutputPort)) (→ Unit) (! mut)
  (write-line out (string-append "PATH: " (set? "PATH")))
  (write-line out (string-append "SNAIL_CWD: " (set? "SNAIL_CWD")))
  (write-line out (string-append "an unset variable: " (set? "SNAIL_TEST_SURELY_UNSET")))
  ;; A relative path resolves against the working directory.
  (match (working-directory)
    ((Some directory)
     (write-line out (if (char=? (string-ref directory 0) #\/) "absolute" "relative"))
     (make-directories fs "build/tests")
     (write-file fs "build/tests/environment-probe.txt" "resolved")
     (write-line out (read-file fs (string-append directory "/build/tests/environment-probe.txt")))
     (remove-file fs "build/tests/environment-probe.txt")
     (unit))
    ((None) (write-line out "no working directory")))
  (unit))
