;; Explicit links preserve provider identity: a fresh link may use a new
;; instance while existing imports and old handles keep their original one.
(import
 (snail core base)
 (snail core io)
 (snail shell wasm))

(define (provider-bytes) (→ Bytes)
  #u8(0 97 115 109 1 0 0 0 1 8 2 96 0 0 96 0 1 127 3 4 3 0 1 1 6 6 1 127 1 65 0 11 7 40 4 7 99
        111 117 110 116 101 114 3 0 11 95 105 110 105 116 105 97 108 105 122 101 0 0 5 118 97
        108 117 101 0 1 4 116 105 99 107 0 2 10 28 3 9 0 35 0 65 1 106 36 0 11 4 0 35 0 11 11 0
        35 0 65 1 106 36 0 35 0 11 0 17 4 110 97 109 101 7 10 1 0 7 99 111 117 110 116 101 114))

(define (a-bytes) (→ Bytes)
  #u8(0 97 115 109 1 0 0 0 1 5 1 96 0 1 127 2 14 1 1 97 7 99 111 117 110 116 101 114 3 127 1 3
        2 1 0 7 9 1 5 118 97 108 117 101 0 0 10 6 1 4 0 35 0 11 0 15 4 110 97 109 101 7 8 1 0 5
        118 97 108 117 101))

(define (compiled (bytes Bytes)) (→ Compiled) (! wasm)
  (match (compile-bytes bytes)
    ((Some module) module)
    ((None) (panic "invalid fixture bytes"))))

(define (provider (compiled Compiled)) (→ Module) (! wasm)
  (match (link-module "provider" compiled (Nil))
    ((Ok instance) instance)
    ((Err _) (panic "provider did not link"))))

(define (answer (instance Module) (name String)) (→ I64) (! wasm)
  (match (run-export instance name 0)
    ((Ok value) value)
    ((Err _) (panic "missing fixture export"))))

(define (expect (label String) (condition Bool)) (→ Unit) (! output-port)
  (if condition (write-line label) (panic label)))

(define (consumer (bytes Compiled) (source Module)) (→ Module) (! wasm)
  (match (link-module "consumer" bytes (list (ExportOf source "counter")))
    ((Ok instance) instance)
    ((Err error) (panic (load-error-message error)))))

(define (main) (→ Unit) (! wasm output-port)
  (let* ((bytes (compiled (provider-bytes)))
         (old (provider bytes)) (updated (provider bytes))
         (reader (compiled (a-bytes)))
         (before (consumer reader old)) (after (consumer reader updated)))
    (expect "initialized once" (= (answer old "tick") 2))
    (expect "existing import keeps provider" (= (answer before "value") 2))
    (expect "new import uses new provider" (= (answer after "value") 1))
    (expect "old handle survives" (= (answer old "tick") 3))
    (expect "existing import observes same instance" (= (answer before "value") 3))
    (expect "linking never reinitializes provider" (= (answer updated "value") 1)))
  (unit))
