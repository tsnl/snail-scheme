;; Exercise the same located project parser as linked Wasm, with a forward
;; run reference and independent build/run name spaces.
(import
 (snail core base)
 (snail core io)
 (snail shell project))

(define project
  (parse-project
   "((run-target café.v2 (run café.v2 (args (\"\" \"--port\" \"8080\"))))
     (build-target client (browser (entry \"client/main.sld\") (public \"public\")))
     (build-target café.v2 (program (entry \"server/main.sld\") (library-roots (\"src\")))))"
   "project.datum"))

(for-each (lambda (target) (write-line (target-name target))) (Project-builds project))
(for-each
 (lambda (run)
   (write-line
    (string-append (RunTarget-name run) " -> " (ProgramBuild-name (RunTarget-program run))))
   (write-line (ProjectPath-text (ProgramBuild-entry (RunTarget-program run))))
   (write-line (string-join (RunTarget-arguments run) "|"))
   (for-each (lambda (path) (write-line (ProjectPath-text path)))
             (ProgramBuild-libraries (RunTarget-program run))))
 (Project-runs project))
