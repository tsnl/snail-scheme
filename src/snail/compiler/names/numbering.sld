;; Fresh numbering: the numbers of one library that no Local, mark, macro
;; or Global's serial of it has yet. `expand` numbers a library's locals,
;; marks and macros from 1, since 0 is the serial of a name the source
;; wrote, and a name a macro's template wrote takes its mark's number as
;; its serial. Each later pass that writes Globals or locals of its own,
;; `bind`, `derive`, `declare` and `dispatch`, numbers them from the first
;; unused number the root of the tree it reads holds, and its own root
;; holds where it stopped. So every number stays unique in its library,
;; and no pass walks a tree to find a free one.
;;
;; A pass threads its Numbering with `state-let*`, or with
;; `result-state-let*` as `(Ok (fresh-local numbering name))` among steps
;; that can fail.
(define-library (snail compiler names numbering)
  (export
   Numbering
   fresh-number
   fresh-global
   fresh-local
   fresh-locals)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries)
   (only (snail compiler names globals) Global Local))
  (begin

    ;; ---- Numbers ----

    ;; `next` is the first number of `library` not handed out.
    (struct Numbering
      ((library LibraryName)
       (next I64)))

    ;; A number no other of the library has, for a mark or a macro.
    (: fresh-number (impl (Fn Numbering -> (Pair I64 Numbering))))
    (define (fresh-number numbering)
      (Pair (::next numbering) (Numbering (::library numbering) (+ (::next numbering) 1))))

    ;; A Global of the library no other has, named `name`, as the entity it
    ;; implements or stands for is, with a serial of its own.
    (: fresh-global (impl (Fn Numbering String -> (Pair Global Numbering))))
    (define (fresh-global numbering name)
      (state-let* ((serial numbering (fresh-number numbering)))
        (Pair (Global (::library numbering) name serial) numbering)))

    ;; A local no other of the library has, named `name`.
    (: fresh-local (impl (Fn Numbering String -> (Pair Local Numbering))))
    (define (fresh-local numbering name)
      (state-let* ((number numbering (fresh-number numbering)))
        (Pair (Local name number) numbering)))

    ;; `count` such locals, in order.
    (: fresh-locals (impl (Fn Numbering String I64 -> (Pair (List Local) Numbering))))
    (define (fresh-locals numbering name count)
      (map-with-state numbering
                      (lambda (numbering index) (fresh-local numbering name))
                      (iota count)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-numbering)
    (import
     (snail stage0 testing))
    (begin
      ;; Numbers, Globals and locals share the numbers, each once.
      (define (test-numbering)
        (let ((numbering (Numbering (list "main") 7)))
          (expect (state-let* ((implementation numbering (fresh-global numbering "show"))
                               (parameters numbering (fresh-locals numbering "argument" 2))
                               (selected numbering (fresh-local numbering "selected"))
                               (mark numbering (fresh-number numbering)))
                    (list implementation parameters selected mark (::next numbering)))
                  (list (Global (list "main") "show" 7)
                        (list (Local "argument" 8) (Local "argument" 9))
                        (Local "selected" 10)
                        11
                        12))
          (expect (fresh-locals numbering "none" 0) (Pair (list) numbering))))))
   (else)))
