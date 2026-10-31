;; File commands Node runs for a program, as host/native/run-snail.mjs
;; provides them: a command is a name and string arguments sent a character
;; at a time, then a number, and a watcher's next hint is a started and
;; finished host operation. (snail shell project files)'s `modes` and
;; (snail shell watch)'s `hints` default to these.
(define-library (snail runtime native files)
  (export
   start-hint
   finish-hint
   argument-character
   argument-end
   command)
  (import
   (snail core base))
  (begin
    (extern start-hint "snail.runtime.native.files" "start-hint" (-> I64 I32 Unit))
    (extern finish-hint "snail.runtime.native.files" "finish-hint" (-> I64 I32))
    (extern argument-character "snail.runtime.native.files" "argument-character" (-> Char Unit))
    (extern argument-end "snail.runtime.native.files" "argument-end" (-> Unit))
    (extern command "snail.runtime.native.files" "command" (-> I32 I32))))
