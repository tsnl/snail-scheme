(import
 (snail core base)
 (snail core io)
 (snail shell compiler read)
 (snail shell compiler session))

;; Arguments: fixture directory, library root and round count. The fixture contains
;; main.sld, sample/helper.sld, before.sld and after.sld.
;; Each round measures a cold build, an unchanged build and one source edit.
;; The caller supplies the same fixture to both compiler revisions.
(define (no-generation (loading (List String)) (forms (List Syntax))) (→ Bytes)
  (panic "the session benchmark has no generated libraries"))

(define (measure (round I64) (label String) (session Session) (source String))
  (→ Session)
  (! mut fs clock output-port compile)
  (let* ((began (monotonic-nanoseconds))
         (built (build-session session source no-generation no-inputs))
         (elapsed (- (monotonic-nanoseconds) began))
         (count (length (filter (lambda (module) (● module compiled?)) (● built first)))))
    (write-line (string-append (i64->string round) " " label " "
                               (i64->string elapsed) " " (i64->string count)))
    (● built second)))

(define (benchmark (arguments (List String))) (→ Unit)
  (! mut fs clock output-port compile)
  (let* ((directory (list-ref arguments 1))
         (source (string-append directory "/main.sld"))
         (library (list-ref arguments 2))
         (edited (string-append directory "/sample/helper.sld"))
         (before (read-file (string-append directory "/before.sld")))
         (after (read-file (string-append directory "/after.sld")))
         (rounds (match (string->i64 (list-ref arguments 3))
                   ((Some count) count)
                   ((None) (panic "expected a round count"))))
         (directories (list directory library)))
    (let loop ((round 0))
      (when (< round rounds)
        (write-file edited before)
        (let* ((cold (measure round "cold" (make-session directories) source))
               (warm (measure round "unchanged" cold source)))
          (write-file edited after)
          (measure round "edited" warm source))
        (loop (+ round 1))))))

(define (main) (→ Unit) (! mut fs clock output-port)
  (match (compiling (lambda () (benchmark (command-line))))
    ((Ok _) (unit))
    ((Err (Failed diagnostics)) (panic (diagnostics->string diagnostics)))
    ((Err (Requested _)) (panic "the session benchmark has no additional inputs"))))
