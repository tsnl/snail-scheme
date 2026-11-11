;; Publish a complete namespace of already initialized instances. This runs
;; unchanged on Node, Wasmtime and Chromium. Consumers import mutable globals:
;; a missing binding must fail to link, and a retained one exposes identity.
(import
 (snail core base)
 (snail core io)
 (snail shell wasm)
 (prefix (snail runtime wasm) host-))

;; (module
;;   (global $counter (export "counter") (mut i32) (i32.const 0))
;;   (func (export "_initialize")
;;     (global.set $counter (i32.add (global.get $counter) (i32.const 1))))
;;   (func (export "value") (result i32) (global.get $counter))
;;   (func (export "tick") (result i32)
;;     (global.set $counter (i32.add (global.get $counter) (i32.const 1)))
;;     (global.get $counter)))
(define provider-bytes (→ Bytes)
  #u8(0 97 115 109 1 0 0 0 1 8 2 96 0 0 96 0 1 127 3 4 3 0 1 1 6 6 1 127 1 65 0 11 7 40 4 7 99
        111 117 110 116 101 114 3 0 11 95 105 110 105 116 105 97 108 105 122 101 0 0 5 118 97
        108 117 101 0 1 4 116 105 99 107 0 2 10 28 3 9 0 35 0 65 1 106 36 0 11 4 0 35 0 11 11 0
        35 0 65 1 106 36 0 35 0 11 0 17 4 110 97 109 101 7 10 1 0 7 99 111 117 110 116 101 114))

;; Each consumer substitutes its library name for "a":
;; (module
;;   (import "a" "counter" (global $value (mut i32)))
;;   (func (export "value") (result i32) (global.get $value)))
(define a-bytes (→ Bytes)
  #u8(0 97 115 109 1 0 0 0 1 5 1 96 0 1 127 2 14 1 1 97 7 99 111 117 110 116 101 114 3 127 1 3
        2 1 0 7 9 1 5 118 97 108 117 101 0 0 10 6 1 4 0 35 0 11 0 15 4 110 97 109 101 7 8 1 0 5
        118 97 108 117 101))

(define kept-bytes (→ Bytes)
  #u8(0 97 115 109 1 0 0 0 1 5 1 96 0 1 127 2 17 1 4 107 101 112 116 7 99 111 117 110 116 101
        114 3 127 1 3 2 1 0 7 9 1 5 118 97 108 117 101 0 0 10 6 1 4 0 35 0 11 0 15 4 110 97 109
        101 7 8 1 0 5 118 97 108 117 101))

(define added-bytes (→ Bytes)
  #u8(0 97 115 109 1 0 0 0 1 5 1 96 0 1 127 2 18 1 5 97 100 100 101 100 7 99 111 117 110 116
        101 114 3 127 1 3 2 1 0 7 9 1 5 118 97 108 117 101 0 0 10 6 1 4 0 35 0 11 0 15 4 110 97
        109 101 7 8 1 0 5 118 97 108 117 101))

(define gone-bytes (→ Bytes)
  #u8(0 97 115 109 1 0 0 0 1 5 1 96 0 1 127 2 17 1 4 103 111 110 101 7 99 111 117 110 116 101
        114 3 127 1 3 2 1 0 7 9 1 5 118 97 108 117 101 0 0 10 6 1 4 0 35 0 11 0 15 4 110 97 109
        101 7 8 1 0 5 118 97 108 117 101))

(define (compiled (bytes Bytes)) (→ Compiled) (! wasm)
  (match (compile-bytes bytes)
    ((Some module) module)
    ((None) (panic "invalid fixture bytes"))))

(define (provider (compiled Compiled)) (→ Module) (! wasm)
  (match (link-module "provider" compiled (Nil))
    ((Ok instance) instance)
    ((Err _) (panic "provider did not link"))))

(define (send-name (name String)) (→ Unit)
  (for-each host-argument-character (string->list name))
  (host-argument-end))

(define (consumer (name String) (compiled Compiled)) (→ (Option Module))
  (send-name name)
  (let ((handle (host-instantiate 0 (::handle compiled))))
    (if (< handle 0) (None) (Some (Module handle)))))

(define (answer (instance Module) (name String)) (→ I64) (! wasm)
  (match (run-export instance name 0)
    ((Ok value) value)
    ((Err _) (panic "missing fixture export"))))

(define (lookup (name String) (compiled Compiled)) (→ I64) (! wasm)
  (match (consumer name compiled)
    ((Some instance) (answer instance "value"))
    ((None) -1)))

(define (expect (label String) (condition Bool)) (→ Unit) (! console)
  (if condition (write-line label) (panic label)))

(define (rejected (label String) (names (List (Pair String Module))) (a Compiled))
  (→ Unit)
  (! wasm console)
  (expect label (not (replace-instances names)))
  (expect (string-append label ": old map kept") (= (lookup label a) 1)))

(let* ((bytes (compiled provider-bytes))
       (old (provider bytes))
       (new (provider bytes))
       (a (compiled a-bytes))
       (kept (compiled kept-bytes))
       (added (compiled added-bytes))
       (gone (compiled gone-bytes)))
  (expect "initialized once" (= (answer old "tick") 2))
  (expect "initial publication" (replace-instances (list (Pair "a" old) (Pair "gone" old))))
  (match (consumer "before" a)
    ((None) (panic "initial namespace unavailable"))
    ((Some before)
     (expect "complete replacement"
             (replace-instances (list (Pair "a" new) (Pair "kept" old) (Pair "added" new))))
     (expect "changed binding" (= (lookup "changed" a) 1))
     (expect "retained identity" (= (lookup "retained" kept) 2))
     (expect "added binding" (= (lookup "added reader" added) 1))
     (expect "removed binding" (= (lookup "removed" gone) -1))
     (expect "existing import survives" (= (answer before "value") 2))
     (expect "old handle survives" (= (answer old "tick") 3))
     (expect "existing import observes same instance" (= (answer before "value") 3))
     (rejected "duplicate name" (list (Pair "a" old) (Pair "a" new)) a)
     (rejected "empty name" (list (Pair "a" old) (Pair "" new)) a)
     (rejected "invalid handle" (list (Pair "a" old) (Pair "bad" (Module -1))) a)
     (rejected "host name" (list (Pair "a" old) (Pair "snail.runtime.wasm" new)) a)
     (rejected "runtime name" (list (Pair "a" old) (Pair "snail.core.support" new)) a)
     (expect "retained binding after failures" (= (lookup "still retained" kept) 3))
     (expect "added binding after failures" (= (lookup "still added" added) 1))
     (host-prepare-names)
     (expect "missing staged name" (not (host-provide-instance (::handle old))))
     (expect "poisoned candidate cannot commit" (not (host-replace-names)))
     (expect "missing name keeps map" (= (lookup "still changed" a) 1))
     (host-prepare-names)
     (send-name "a")
     (expect "candidate staged" (host-provide-instance (::handle old)))
     (expect "staging leaves map intact" (= (lookup "during staging" a) 1))
     (host-prepare-names)
     (expect "new preparation discards previous candidate" (host-replace-names))
     (expect "empty candidate removes bindings" (= (lookup "empty" a) -1))
     (expect "commit consumes candidate" (not (host-replace-names)))
     (send-name "a")
     (expect "entry without preparation" (not (host-provide-instance (::handle old))))
     (expect "no partial publication" (not (host-replace-names)))
     (expect "empty replacement" (replace-instances (Nil)))
     (expect "empty replacement preserves handles" (= (answer before "value") 3))
     (expect "publication never reinitializes" (= (answer new "value") 1)))))
