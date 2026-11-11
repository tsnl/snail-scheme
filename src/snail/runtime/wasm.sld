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
   call-export
   call-with-function)
  (import
   (snail core base)
   (only (snail core forms) Funcref))
  (begin
    (extern argument-character "snail.runtime.wasm" "argument-character" (impl (Fn Char -> Unit)))
    (extern argument-end "snail.runtime.wasm" "argument-end" (impl (Fn -> Unit)))
    (extern compile "snail.runtime.wasm" "compile" (impl (Fn Bytes -> I32)))
    (extern namespace "snail.runtime.wasm" "namespace" (impl (Fn -> I32)))
    (extern instantiate "snail.runtime.wasm" "instantiate" (impl (Fn I32 I32 -> I32)))
    (extern has-export "snail.runtime.wasm" "has-export" (impl (Fn I32 -> Bool)))
    (extern export-function "snail.runtime.wasm" "export-function" (impl (Fn I32 -> Funcref)))
    (extern import-count "snail.runtime.wasm" "import-count" (impl (Fn I32 -> I32)))
    (extern import-at "snail.runtime.wasm" "import-at" (impl (Fn I32 I32 -> I32)))
    (extern held-length "snail.runtime.wasm" "held-length" (impl (Fn I32 -> I32)))
    (extern held-char "snail.runtime.wasm" "held-char" (impl (Fn I32 I32 -> Char)))
    (extern prepare-link "snail.runtime.wasm" "prepare-link" (impl (Fn I32 -> Unit)))
    (extern provide-export "snail.runtime.wasm" "provide-export" (impl (Fn I32 -> Bool)))
    (extern provide-host "snail.runtime.wasm" "provide-host" (impl (Fn -> Bool)))
    (extern provide-missing "snail.runtime.wasm" "provide-missing" (impl (Fn -> Unit)))
    (extern link-prepared "snail.runtime.wasm" "link-prepared" (impl (Fn -> I32)))
    (extern provide-constant "snail.runtime.wasm" "provide-constant" (impl (Fn I32 -> Unit)))
    (extern name-instance "snail.runtime.wasm" "name-instance" (impl (Fn I32 -> Bool)))
    (extern prepare-names "snail.runtime.wasm" "prepare-names" (impl (Fn -> Unit)))
    (extern provide-instance "snail.runtime.wasm" "provide-instance" (impl (Fn I32 -> Bool)))
    (extern replace-names "snail.runtime.wasm" "replace-names" (impl (Fn -> Bool)))
    (extern call-export "snail.runtime.wasm" "call-export" (impl (Fn I32 I64 -> I64)))
    (extern call-with-function
            "snail.runtime.wasm"
            "call-with-function"
            (impl (Fn I32 Funcref -> I64)))))
