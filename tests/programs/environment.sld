(import
 (snail core base)
 (snail core io))

;; The environment and the working directory, as total reads. The suite runs
;; with PATH set; the host's own channel for the working directory is hidden.
(: set? (-> String String))
(define (set? name)
  (match (environment-variable name)
    ((Some value) (if (string=? value "") "set, empty" "set"))
    ((None) "unset")))

(write-line (string-append "PATH: " (set? "PATH")))
(write-line (string-append "SNAIL_CWD: " (set? "SNAIL_CWD")))
(write-line (string-append "an unset variable: " (set? "SNAIL_TEST_SURELY_UNSET")))

;; A relative path resolves against the working directory.
(match (working-directory)
  ((Some directory)
   (write-line (if (char=? (string-ref directory 0) #\/) "absolute" "relative"))
   (make-directories "build/tests")
   (write-file "build/tests/environment-probe.txt" "resolved")
   (write-line (read-file (string-append directory "/build/tests/environment-probe.txt")))
   (remove-file "build/tests/environment-probe.txt")
   (unit))
  ((None) (write-line "no working directory")))
