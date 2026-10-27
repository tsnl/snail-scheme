;; Runtime-owned control operations. Dispatch transfers one-shot local work;
;; its latent effects remain requirements of the dispatching computation.
(define-library (snail-core task)
  (export tasks dispatch-local yield sleep)
  (import
   (only (snail-core core) tasks)
   (only (snail-core primitive) dispatch-local)
   (rename (only (snail-core primitive) yield-task sleep-task)
           (yield-task yield)
           (sleep-task sleep))))
