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
   prepare-names
   provide-instance
   replace-names
   call-export)
  (import
   (snail core base)
   (only (snail core forms) Funcref))
  (begin
    (extern argument-character "snail.runtime.wasm" "argument-character" (Fn Char → Unit))
    (extern argument-end "snail.runtime.wasm" "argument-end" (Fn → Unit))
    (extern compile "snail.runtime.wasm" "compile" (Fn Bytes → I32))
    (extern namespace "snail.runtime.wasm" "namespace" (Fn → I32))
    (extern instantiate "snail.runtime.wasm" "instantiate" (Fn I32 I32 → I32))
    (extern has-export "snail.runtime.wasm" "has-export" (Fn I32 → Bool))
    (extern export-function "snail.runtime.wasm" "export-function" (Fn I32 → Funcref))
    (extern import-count "snail.runtime.wasm" "import-count" (Fn I32 → I32))
    (extern import-at "snail.runtime.wasm" "import-at" (Fn I32 I32 → I32))
    (extern held-length "snail.runtime.wasm" "held-length" (Fn I32 → I32))
    (extern held-char "snail.runtime.wasm" "held-char" (Fn I32 I32 → Char))
    (extern prepare-link "snail.runtime.wasm" "prepare-link" (Fn I32 → Unit))
    (extern provide-export "snail.runtime.wasm" "provide-export" (Fn I32 → Bool))
    (extern provide-host "snail.runtime.wasm" "provide-host" (Fn → Bool))
    (extern provide-missing "snail.runtime.wasm" "provide-missing" (Fn → Unit))
    (extern link-prepared "snail.runtime.wasm" "link-prepared" (Fn → I32))
    (extern provide-constant "snail.runtime.wasm" "provide-constant" (Fn I32 → Unit))
    (extern name-instance "snail.runtime.wasm" "name-instance" (Fn I32 → Bool))
    (extern prepare-names "snail.runtime.wasm" "prepare-names" (Fn → Unit))
    (extern provide-instance "snail.runtime.wasm" "provide-instance" (Fn I32 → Bool))
    (extern replace-names "snail.runtime.wasm" "replace-names" (Fn → Bool))
    (extern call-export "snail.runtime.wasm" "call-export" (Fn I32 I64 → I64))
    ))
