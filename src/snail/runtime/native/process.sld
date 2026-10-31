;; Node's child processes and termination signals, as
;; host/native/process-imports.mjs provides them, answered as
;; (snail runtime native socket) answers. A command is sent first, a string
;; at a time, each a character at a time and ended by `argument-end`: its
;; directory, its program, then its arguments. `start-spawn`, `run` and
;; `exec` take the command sent last. A process crosses as the host's
;; handle, which is never 0, and a stream as its descriptor.
;;
;;   operation          answer                number     byte strings
;;   spawn              the handle            its id
;;   read-output        1, or 0 at the end               the bytes
;;   write-input        the count written
;;   wait-exit          0 exited, 1 signaled  its code   the signal's name
;;   run                as wait-exit          its code   the signal's name,
;;                                                       stdout, stderr
;;   termination        the signal's number
;;   close-input,
;;   send-signal,
;;   close-process      0
;;   exec               only a failure
(define-library (snail runtime native process)
  (export
   argument-character
   argument-end
   start-spawn
   start-read-output
   start-write-input
   start-wait-exit
   start-termination
   finish
   close-input
   send-signal
   close-process
   run
   exec
   held-number
   held-length
   held-byte)
  (import
   (snail core base))
  (begin
    (extern argument-character "snail.runtime.native.process" "argument-character" (-> Char Unit))
    (extern argument-end "snail.runtime.native.process" "argument-end" (-> Unit))
    (extern start-spawn "snail.runtime.native.process" "start-spawn" (-> I64 Unit))
    (extern start-read-output
            "snail.runtime.native.process"
            "start-read-output"
            (-> I64 I32 I32 I32 Unit))
    (extern start-write-input
            "snail.runtime.native.process"
            "start-write-input"
            (-> I64 I32 Bytes Unit))
    (extern start-wait-exit "snail.runtime.native.process" "start-wait-exit" (-> I64 I32 Unit))
    (extern start-termination "snail.runtime.native.process" "start-termination" (-> I64 Unit))
    (extern finish "snail.runtime.native.process" "finish" (-> I64 I32))
    (extern close-input "snail.runtime.native.process" "close-input" (-> I32 I32))
    (extern send-signal "snail.runtime.native.process" "send-signal" (-> I32 I32 I32))
    (extern close-process "snail.runtime.native.process" "close-process" (-> I32 I32))
    (extern run "snail.runtime.native.process" "run" (-> Bytes I32))
    (extern exec "snail.runtime.native.process" "exec" (-> I32))
    (extern held-number "snail.runtime.native.process" "held-number" (-> I32))
    (extern held-length "snail.runtime.native.process" "held-length" (-> I32 I32))
    (extern held-byte "snail.runtime.native.process" "held-byte" (-> I32 I32 I32))))
