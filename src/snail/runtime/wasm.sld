;; Compiling and instantiating WebAssembly modules, as host/native/run-snail.mjs
;; and crates/snail provide it: a module is compiled from bytes into a
;; handle, instantiated in a namespace, or linked against providers chosen
;; one per import, and its exports are found by name, sent a character at a
;; time; a name the host holds comes back a character at a time. (snail
;; shell wasm)'s `wasm` effect defaults to these.
(define-library (snail runtime wasm)
  (export
   argument-character
   argument-end
   compile
   namespace
   instantiate
   has-export
   export-function
   import-count
   import-at
   held-length
   held-char
   prepare-link
   provide-export
   provide-host
   provide-missing
   link-prepared
   provide-constant
   name-instance
   call-export)
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
    (extern export-function "snail.runtime.wasm" "export-function" (-> I32 Funcref))
    (extern import-count "snail.runtime.wasm" "import-count" (-> I32 I32))
    (extern import-at "snail.runtime.wasm" "import-at" (-> I32 I32 I32))
    (extern held-length "snail.runtime.wasm" "held-length" (-> I32 I32))
    (extern held-char "snail.runtime.wasm" "held-char" (-> I32 I32 Char))
    (extern prepare-link "snail.runtime.wasm" "prepare-link" (-> I32 Unit))
    (extern provide-export "snail.runtime.wasm" "provide-export" (-> I32 Bool))
    (extern provide-host "snail.runtime.wasm" "provide-host" (-> Bool))
    (extern provide-missing "snail.runtime.wasm" "provide-missing" (-> Unit))
    (extern link-prepared "snail.runtime.wasm" "link-prepared" (-> I32))
    (extern provide-constant "snail.runtime.wasm" "provide-constant" (-> I32 Unit))
    (extern name-instance "snail.runtime.wasm" "name-instance" (-> I32 Bool))
    (extern call-export "snail.runtime.wasm" "call-export" (-> I32 I64 I64))))
