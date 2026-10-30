(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell ui))

;; The reconciler's cases, a view per step, each click on "next" moving to
;; the next. The trace after each "fire" line is what one step changed:
;; an attribute removed and a flag property cleared (step 1), keyed
;; children inserted at the front (1) and in the middle (2), an element
;; whose tag changed replaced and a text replaced by an element (2), a
;; listener made again when its captures change (3), and keyed children
;; removed and reordered (4).

(enum Msg
  (Next))

(: update (-> I64 Msg (Pair I64 (List (FnOnce Msg ! tasks)))))
(define (update step message)
  (Pair (+ step 1) (Nil)))

(: view (-> I64 (Html Msg)))
(define (view step)
  (Element "div"
           (Nil)
           (list (Element "button"
                          (list (Attr "id" "next")
                                (On "click"
                                    (if (>= step 3) (list (Pointer)) (Nil))
                                    (Allow)
                                    (lambda (event) (Next))))
                          (list (Text "next")))
                 (if (>= step 2)
                     (Element "span" (Nil) (list (Text "two")))
                     (Element "p"
                              (if (= step 0) (list (Attr "class" "first")) (Nil))
                              (list (Text (if (= step 0) "zero" "one")))))
                 (if (>= step 2) (Element "em" (Nil) (list (Text "tail"))) (Text "tail"))
                 (Element "input" (if (= step 0) (list (FlagProperty "disabled" #t)) (Nil)) (Nil))
                 (Element "ul" (Nil) (map item (items step))))))

(: items (-> I64 (List String)))
(define (items step)
  (cond ((= step 0) (list "b" "c"))
        ((= step 1) (list "a" "b" "c"))
        ((< step 4) (list "a" "x" "b" "c"))
        (else (list "c" "b"))))

(: item (-> String (Html Msg)))
(define (item name)
  (Element "li" (list (Keyed name)) (list (Text name))))

(dispatch-local
 (once (lambda ()
         (let ((result (with-memory-dom (list (Fire "next" "click" no-event)
                                              (Fire "next" "click" no-event)
                                              (Fire "next" "click" no-event)
                                              (Fire "next" "click" no-event))
                                        (lambda () (run-ui 0 update view (lambda (step) (unit)))))))
           (write-line (string-append "step " (show (Pair-first result))))
           (write-line (document->html (Pair-second result)))
           (for-each write-line (document-trace (Pair-second result)))))))
