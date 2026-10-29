(import
 (snail core base))

;; A non-regular declaration nests its parameter deeper at each level, so
;; its instantiations never repeat. Asking whether `nest` is linear must
;; still end, and the error reported is the work item's second use.
(enum (Nest T)
  (Flat)
  (Deeper ((value T)
           (rest (Nest (Pair T T))))))

(let ((work (once (lambda () (unit))))
      (nest (Deeper 1 (Flat))))
  (match nest
    ((Flat) (unit))
    ((Deeper value rest) (unit)))
  (call-once work)
  (call-once work))
