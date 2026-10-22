;; The development server's program when it runs as WebAssembly under Node:
;;
;;   develop ROOT RUNTIME CLIENT serve PORT APP-DIRECTORY
;;   develop ROOT RUNTIME CLIENT watch SOURCE DIRECTORY ... -- ARGUMENT ...
;;
;; the loop of (lofi develop), which builds first, with the files of the
;; machine it runs on, and its events from scripts/develop.mjs.
(import
 (lofi base)
 (lofi develop))

(expose develop-character "develop_character")
(expose develop-event "develop_event")

(start-development!)
