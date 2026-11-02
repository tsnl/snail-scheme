;; The native engine, which stage 0 builds (`scripts/snail-tool cli-tools`)
;; and host/native/run-snail.mjs and `snail run-wasm` start to run a
;; program compiled one library at a time: SNAIL_MANIFEST names its
;; modules.json, and the host sees the program's scheduler and its runtime
;; through the exports below ((snail shell engine)).
(import
 (snail core base)
 (snail core io)
 (snail shell engine))

(expose tasks-turn "tasks:turn")
(expose tasks-wake "tasks:wake")
(expose tasks-close "tasks:close")
(expose tasks-running "tasks:running")
(expose tasks-live "tasks:live")
(expose resource-read "resource:read")
(expose resource-finish "resource:finish")
(expose resource-byte "resource:byte")
(expose program-status "engine:status")
(expose close-program "engine:close")

(match (environment-variable "SNAIL_MANIFEST")
  ((Some manifest) (run-manifest manifest) (unit))
  ((None) (panic "the engine needs SNAIL_MANIFEST, the modules.json of the program to run")))
