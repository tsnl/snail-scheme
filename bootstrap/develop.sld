;; The development server's program when it runs as WebAssembly under Node:
;;
;;   develop ROOT RUNTIME CLIENT serve PORT APP-DIRECTORY
;;   develop ROOT RUNTIME CLIENT watch SOURCE DIRECTORY ... -- ARGUMENT ...
;;
;; the loop of (lofi develop), with the machine's files and events from
;; scripts/develop.mjs, running in scripts/develop-worker.mjs. It installs
;; watches and schedules its initial build through the existing timer event.
(import
 (lofi base)
 (lofi develop))

(expose develop-character "develop_character")
(expose develop-event "develop_event")

(start-development!)
