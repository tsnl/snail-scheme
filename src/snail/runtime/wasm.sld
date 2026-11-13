;; Compiling and instantiating WebAssembly modules, as host/native/run-snail.mjs
;; and crates/snail provide it: a module is compiled from bytes into a
;; handle, linked against providers chosen
;; one per import, and its exports are found by name, sent a character at a
;; time; a name the host holds comes back a character at a time. (snail
;; shell wasm)'s `wasm` effect defaults to these.
(define-library (snail runtime wasm)
  (export
   argument-character
   argument-end
   compile
   bind-runtime
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
   call-export)
  (import
   (snail core base)
   (only (snail core forms) Funcref))
  (begin
    (extern argument-character "snail.runtime.wasm" "argument-character" (Fn Char → Unit))
    (extern argument-end "snail.runtime.wasm" "argument-end" (Fn → Unit))
    (extern bind-runtime "snail.runtime.wasm" "bind-runtime" (Fn I32 → Unit))
    (extern compile "snail.runtime.wasm" "compile" (Fn Bytes → I32))

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

    (extern call-export "snail.runtime.wasm" "call-export" (Fn I32 I64 → I64))
    ))
