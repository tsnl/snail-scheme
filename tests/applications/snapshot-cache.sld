;; Real managed caches with tiny scalar states isolate bank identity and lifetime.
(define-library (snapshot-cache)
  (export answer)
  (import
   (scheme base)
   (application reducer)
   (application bridge)
   (browser application)
   (only (lofi core) ann -> I32 I64)
   (only (lofi base) unreachable))
  (begin
    (define (encode value) (vector (ann 1 I32) value))
    (define (decode words)
      (unless (= (vector-length words) (ann 2 I64)) (unreachable))
      (let ((value (vector-ref words (ann 1 I64))))
        (when (< value 0) (unreachable)) value))
    (application world (state I32 1) 0
                 (add (value (amount I32)) (transition (+ value amount) (list (notice "saved"))))
                 (invalid (value) (no-effects -1)))
    (application local (state I32 1) 0
                 (remember (value) (no-effects (read-program-world app))))
    (define (view world local)
      (list (quad world local (read-program-previous-world app) (read-program-previous-local app) 0 255)))
    (define (status world local) "cache")
    (define app (program world local 2 2 decode encode decode encode view status))
    (define answer
      (ann (lambda (operation a b c) (run-program app operation a b c))
           (-> I32 I32 I32 I32 I32)))))
