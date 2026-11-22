;; The client page, built when this library is: its producer builds
;; client/main.scm for the browser, and the library links every file of
;; that build.
(generate-library (embedded client)
                  (import
                   (snail core base)
                   (snail shell project build)
                   (embedded linking)
                   (only (snail core io) Arguments ProcessEnvironment Fs Clock)
                   (only (snail shell process) Processes))
                  (lambda ((arguments Arguments)
                           (environment ProcessEnvironment)
                           (processes Processes)
                           (fs Fs)
                           (clock Clock))
                    (files-library fs (list "embedded" "client")
                                   "client-files"
                                   (build-script processes fs clock (producer-tools arguments)
                                                 (script-at fs environment "client/main.scm")
                                                 (Browser)
                                                 (Debug)))))
