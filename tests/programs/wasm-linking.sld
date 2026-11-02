;; The host's Wasm primitives as a loader written in Snail-Core uses them:
;; a module's imports listed, each given a provider, the module linked and
;; an export run. The two hosts must answer alike: this runs on Node in
;; `make test` and on wasmtime in `make test-wasmtime`. `one` exports a
;; function and a global; `two` imports both, a function of the host's,
;; and one that is given a constant, or nothing. Providers follow the
;; module's import order, which is the binary's: Binaryen wrote the global
;; import first.
(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

;; (module
;;   (func (export "one") (result i32) (i32.const 1))
;;   (global (export "limit") i32 (i32.const 7)))
(: one-bytes Bytes)
(define one-bytes
  #u8(0 97 115 109 1 0 0 0 1 5 1 96 0 1 127 3 2 1 0 6 6 1 127 0 65 7 11 7 15 2 3 111 110 101 0 0
        5 108 105 109 105 116 3 0 10 6 1 4 0 65 1 11))

;; (module
;;   (import "one" "one" (func $one (result i32)))
;;   (import "one" "limit" (global $limit i32))
;;   (import "snail.runtime.wasm" "namespace" (func $namespace (result i32)))
;;   (import "host" "missing" (func $missing (result i32)))
;;   (func (export "main") (result i32)
;;     (i32.add (call $one) (i32.add (global.get $limit) (i32.const 34))))
;;   (func (export "fail") (result i32) (call $missing)))
(: two-bytes Bytes)
(define two-bytes
  #u8(0 97 115 109 1 0 0 0 1 5 1 96 0 1 127 2 70 4 3 111 110 101 5 108 105 109 105 116 3 127 0 3
        111 110 101 3 111 110 101 0 0 18 115 110 97 105 108 46 114 117 110 116 105 109 101 46 119
        97 115 109 9 110 97 109 101 115 112 97 99 101 0 0 4 104 111 115 116 7 109 105 115 115 105
        110 103 0 0 3 3 2 0 0 7 15 2 4 109 97 105 110 0 3 4 102 97 105 108 0 4 10 17 2 10 0 16 0
        35 0 65 34 106 106 11 4 0 16 2 11))

(: compiled (-> String Bytes Compiled ! wasm))
(define (compiled name bytes)
  (match (compile-bytes bytes)
    ((Some module) module)
    ((None) (panic (string-append name " is not a module")))))

(: kind-name (-> ImportKind String))
(define (kind-name kind)
  (match kind
    ((FunctionImport) "function")
    ((TableImport) "table")
    ((MemoryImport) "memory")
    ((GlobalImport) "global")))

(: show-import (-> Import Unit ! console))
(define (show-import import)
  (write-line (string-append (Import-from import) " " (Import-name import) " "
                             (kind-name (Import-kind import)))))

(: show-run (-> Module String Unit ! wasm console))
(define (show-run instance name)
  (match (run-export instance name 0)
    ((Ok answer) (write-line (string-append name " answers " (show answer))))
    ((Err error) (write-line (load-error-message error)))))

(: providers (-> Module String Provider (List Provider)))
(define (providers one export missing)
  (list (ExportOf one "limit") (ExportOf one export) (HostProvided) missing))

(let ((one (compiled "one" one-bytes)) (two (compiled "two" two-bytes)))
  (write-line (string-append "one imports " (show (length (module-imports one)))))
  (for-each show-import (module-imports two))
  (match (link-module "one" one (Nil))
    ((Ok linked-one)
     (match (link-module "two" two (providers linked-one "one" (ConstantOf 5)))
       ((Ok linked-two)
        (show-run linked-two "main")
        (show-run linked-two "fail")
        (show-run linked-two "absent")
        (write-line (if (name-instance linked-two "two") "named two" "two is taken"))
        (write-line (if (name-instance linked-two "two") "named two" "two is taken")))
       ((Err error) (write-line (load-error-message error))))
     (match (link-module "two again" two (providers linked-one "nothing" (Unprovided)))
       ((Ok _) (write-line "linked without its provider"))
       ((Err error) (write-line (load-error-message error))))
     (match (link-module "two short" two (list (ExportOf linked-one "limit")))
       ((Ok _) (write-line "linked with an import unprovided"))
       ((Err error) (write-line (load-error-message error)))))
    ((Err error) (write-line (load-error-message error)))))

(match (compile-bytes #u8(1 2 3))
  ((Some _) (write-line "bytes that are no module compiled"))
  ((None) (write-line "not a module")))
