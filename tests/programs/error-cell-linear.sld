(import
 (snail core base))

;; A cell holds no linear value: it is shared, so nothing could finalize
;; what it held when it was lost. Own the work item in a frame instead, or
;; rest it in the runtime's slot between tasks.
(let ((cell (ref (once (lambda () (unit))))))
  (unit))
