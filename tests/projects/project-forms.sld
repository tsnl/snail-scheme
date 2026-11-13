;; Exercise the same located project parser as linked Wasm, with a forward
;; run reference and independent build/run name spaces.
(import
 (snail core base)
 (snail core io)
 (snail shell project)
 (only (snail shell compiler read)
       compiling
       diagnostics->string
       Failed))

(define (project) (→ Project)
  (match (compiling
          (lambda ()
            (parse-project
             "((run-target café.v2 (run café.v2 (args (\"\" \"--port\" \"8080\"))))
     (build-target client (browser (entry \"client/main.sld\") (public \"public\")))
     (build-target café.v2 (program (entry \"server/main.sld\") (library-roots (\"src\")))))"
             "project.datum")))
    ((Ok parsed) parsed)
    ((Err (Failed diagnostics)) (panic (diagnostics->string diagnostics)))
    ((Err _) (panic "parsing a project asked for an input"))))

(define (main) (→ Unit) (! output-port)

  (for-each (lambda (target) (write-line (target-name target))) (● (project) builds))
  (for-each
   (lambda (run)
     (write-line
      (string-append (● run name) " -> " (● (● run program) name)))
     (match (● (● run program) entry)
       ((SourceEntry path) (write-line (● path text)))
       (_ (panic "expected a source entry")))
     (write-line (string-join (● run arguments) "|"))
     (for-each (lambda (path) (write-line (● path text)))
               (● (● run program) libraries)))
   (● (project) runs))
  (unit))
