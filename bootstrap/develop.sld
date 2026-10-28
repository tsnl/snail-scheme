;; The development server's program when it runs as WebAssembly under Node:
;;
;;   develop ROOT RUNTIME CLIENT serve PORT APP-DIRECTORY
;;   develop ROOT RUNTIME CLIENT watch SOURCE DIRECTORY ... -- ARGUMENT ...
;;
;; the loop of (snail shell develop), with the machine's files and events from
;; host/native/develop.mjs, running in host/native/develop-worker.mjs. It installs
;; watches and schedules its initial build through the existing timer event.
(import
 (snail core base)
 (snail shell develop))

(expose develop-character "develop_character")
(expose develop-event "develop_event")

(start-development!)
