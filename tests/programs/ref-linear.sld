(import
 (snail core base)
 (snail core io))

(type Work (Once (-> Unit ! console)))

(: say (-> String Work))
(define (say text)
  (once (lambda () (write-line text))))

;; A Ref's handle is unrestricted even when its content is linear: the
;; queue below is named three times. `ref-replace!` takes the content out
;; and puts the next in, so no work item is ever in two places.
(: enqueue! (-> (Ref (List Work)) Work Unit ! mut))
(define (enqueue! queue work)
  (put-back! queue (append (ref-replace! queue (Nil)) (list work))))

;; A queue whose content was taken out holds the empty list the swap left,
;; which matching consumes. Anything else means a second writer.
(: put-back! (-> (Ref (List Work)) (List Work) Unit ! mut))
(define (put-back! queue items)
  (match (ref-replace! queue items)
    ((Nil) (unit))
    ((Cons work rest) (panic "the queue changed while its content was out"))))

(: run-all! (-> (Ref (List Work)) Unit ! mut console))
(define (run-all! queue)
  (match (ref-replace! queue (Nil))
    ((Nil) (unit))
    ((Cons work rest) (put-back! queue rest) (call-once work) (run-all! queue))))

(let ((queue (ref (Nil))))
  (enqueue! queue (say "one"))
  (enqueue! queue (say "two"))
  (run-all! queue))

;; A global may hold one too, since the handle is what the global names.
(: pending (Ref (List Work)))
(define pending (ref (list (say "three"))))

(run-all! pending)
