;; Exercise the same located project parser as linked Wasm, with a forward
;; launch reference and independent build/launch name spaces.
(import
 (lofi base)
 (lofi io)
 (lofi project))

(define project
  (parse-project
   "((launch-target dev (run dev (args \"\" \"--port\" \"8080\")))
     (build-target client (browser (entry \"client/main.sld\") (public \"public\")))
     (build-target dev (program (entry \"server/main.sld\") (library-roots \"src\"))))"
   "project.datum"))

(for-each (lambda (target) (write-line (target-name target))) (Project-builds project))
(for-each
 (lambda (launch)
   (write-line (string-append (LaunchTarget-name launch) " -> " (ProgramBuild-name (LaunchTarget-program launch))))
   (write-line (ProjectPath-text (ProgramBuild-entry (LaunchTarget-program launch))))
   (write-line (string-join (LaunchTarget-arguments launch) "|"))
   (for-each (lambda (path) (write-line (ProjectPath-text path))) (ProgramBuild-libraries (LaunchTarget-program launch))))
 (Project-launches project))
