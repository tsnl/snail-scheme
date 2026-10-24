;; Runtime-owned control operations. Dispatch transfers one-shot local work;
;; its latent effects remain requirements of the dispatching computation.
(define-library (lofi task)
  (export tasks dispatch-local yield sleep)
  (import
   (only (lofi core) tasks)
   (only (lofi primitive) dispatch-local)
   (rename (only (lofi primitive) yield-task sleep-task)
           (yield-task yield)
           (sleep-task sleep))))
