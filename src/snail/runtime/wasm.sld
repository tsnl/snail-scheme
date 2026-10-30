;; Compiling and instantiating WebAssembly modules, as host/native/run-snail.mjs
;; provides it: a module is compiled from bytes into a handle, instantiated in a
;; namespace, and its exports are found by name, sent a character at a time.
;; (snail shell wasm)'s `wasm` effect defaults to these.
(define-library (snail runtime wasm)
  (export
   argument-character
   argument-end
   compile
   namespace
   instantiate
   has-export
   export-function)
  (import
   (snail core base)
   (only (snail core forms) Funcref))
  (begin
    (extern argument-character "snail.runtime.wasm" "argument-character" (-> Char Unit))
    (extern argument-end "snail.runtime.wasm" "argument-end" (-> Unit))
    (extern compile "snail.runtime.wasm" "compile" (-> Bytes I32))
    (extern namespace "snail.runtime.wasm" "namespace" (-> I32))
    (extern instantiate "snail.runtime.wasm" "instantiate" (-> I32 I32 I32))
    (extern has-export "snail.runtime.wasm" "has-export" (-> I32 Bool))
    (extern export-function "snail.runtime.wasm" "export-function" (-> I32 Funcref))))
