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

(define (compiled (wasm Wasm) (bytes Bytes)) (→ Compiled)
  (match (compile-bytes wasm bytes)
    ((Some module) module)
    ((None) (panic "invalid fixture bytes"))))

(define (provider (wasm Wasm) (compiled Compiled)) (→ Module)
  (match (link-module wasm "provider" compiled (Nil))
    ((Ok instance) instance)
    ((Err _) (panic "provider did not link"))))

(define (answer (wasm Wasm) (instance Module) (name String)) (→ I64)
  (match (run-export wasm instance name 0)
    ((Ok value) value)
    ((Err _) (panic "missing fixture export"))))

(define (expect (out OutputPort) (label String) (condition Bool)) (→ Unit)
  (if condition (write-line out label) (panic label)))

(define (consumer (wasm Wasm) (bytes Compiled) (source Module)) (→ Module)
  (match (link-module wasm "consumer" bytes (list (ExportOf source "counter")))
    ((Ok instance) instance)
    ((Err error) (panic (load-error-message error)))))

(define (main (wasm Wasm) (out OutputPort)) (→ Unit)
  (let* ((bytes (compiled wasm (provider-bytes)))
         (old (provider wasm bytes)) (updated (provider wasm bytes))
         (reader (compiled wasm (a-bytes)))
         (before (consumer wasm reader old)) (after (consumer wasm reader updated)))
    (expect out "initialized once" (= (answer wasm old "tick") 2))
    (expect out "existing import keeps provider" (= (answer wasm before "value") 2))
    (expect out "new import uses new provider" (= (answer wasm after "value") 1))
    (expect out "old handle survives" (= (answer wasm old "tick") 3))
    (expect out "existing import observes same instance" (= (answer wasm before "value") 3))
    (expect out "linking never reinitializes provider" (= (answer wasm updated "value") 1)))
  (unit))
