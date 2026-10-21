;; Kernels: a Scheme environment over typed Lofi values, which a host sends
;; text to evaluate, as a REPL or a notebook does. A kernel program names the
;; values its Scheme code may use:
;;
;;   (define-opaque Random "random")
;;   (define-kernel
;;    ("make-random" make-random)
;;    ("random-below" random-below))
;;
;; `define-kernel` converts each value with `Dynamic`, binds it in a
;; standard environment, and exposes the entry points that the hosts in
;; src/notebook call. A host sends the text one character at a time, asks
;; for it to be evaluated, and reads back the written value one character at
;; a time. What the code prints goes to standard output. An error panics,
;; which stops the evaluation; the host reports it and goes on with the same
;; kernel, whose definitions are kept.
(define-library (lofi kernel)
  (export
   define-kernel
   Datum
   Dynamic
   to-datum
   from-datum
   define-opaque)
  (import
   (lofi base)
   (lofi io)
   (lofi datum)
   (lofi write)
   (scheme eval))
  (begin

    ;; ---- Kernels ----

    ;; The environment, the text being received, and the text of the last
    ;; result.
    (struct Kernel
      ((environment Environment)
       (input (Ref (Array Char)))
       (result (Ref String))))

    (: make-kernel (-> (List (Pair String Datum)) Kernel ! mut))
    (define (make-kernel bindings)
      (let ((environment (standard-environment)))
        (for-each (lambda (binding) (environment-define! environment (Pair-first binding) (Pair-second binding))) bindings)
        (Kernel environment (ref (make-array 0 #\space)) (ref ""))))

    (: receive-begin! (-> Kernel I32 Unit ! mut))
    (define (receive-begin! kernel count)
      (ref-set! (Kernel-input kernel) (make-array (i32->i64 count) #\space)))

    (: receive-character! (-> Kernel I32 I32 Unit ! mut))
    (define (receive-character! kernel index code)
      (array-set! (ref-get (Kernel-input kernel)) (i32->i64 index) (i32->char code)))

    ;; Evaluates the text received. Returns 1 when the value is one to show,
    ;; and its written text becomes the result, or 0 when it is unspecified.
    (: evaluate! (-> Kernel I32 ! console mut))
    (define (evaluate! kernel)
      (let ((value (eval-text (vector->string (array->vector (ref-get (Kernel-input kernel)))) (Kernel-environment kernel))))
        (match value
          ((UnspecifiedDatum) (ref-set! (Kernel-result kernel) "") 0)
          (_ (ref-set! (Kernel-result kernel) (datum->string value)) 1))))

    ;; The defined names, one to a line, become the result; returns how many
    ;; there are.
    (: names! (-> Kernel I32 ! mut))
    (define (names! kernel)
      (let ((names (environment-names (Kernel-environment kernel))))
        (ref-set! (Kernel-result kernel) (string-join names "\n"))
        (i64->i32 (length names))))

    (: result-length (-> Kernel I32 ! mut))
    (define (result-length kernel)
      (i64->i32 (string-length (ref-get (Kernel-result kernel)))))

    (: result-character (-> Kernel I32 I32 ! mut))
    (define (result-character kernel index)
      (char->i32 (string-ref (ref-get (Kernel-result kernel)) (i32->i64 index))))

    ;; ---- Entry points ----

    ;; `(define-kernel ("name" value) ...)` makes the program a kernel in
    ;; which each name is bound to its value. Each value's type needs a
    ;; `Dynamic` instance.
    (define-syntax define-kernel
      (syntax-rules ()
        ((_ (name value) ...)
         (begin
           (define kernel (make-kernel (list (Pair name (to-datum value)) ...)))

           (: kernel-input-begin (-> I32 Unit ! mut))
           (define (kernel-input-begin count)
             (receive-begin! kernel count))

           (: kernel-input-character (-> I32 I32 Unit ! mut))
           (define (kernel-input-character index code)
             (receive-character! kernel index code))

           (: kernel-evaluate (-> I32 ! console mut))
           (define (kernel-evaluate)
             (evaluate! kernel))

           (: kernel-names (-> I32 ! mut))
           (define (kernel-names)
             (names! kernel))

           (: kernel-result-length (-> I32 ! mut))
           (define (kernel-result-length)
             (result-length kernel))

           (: kernel-result-character (-> I32 I32 ! mut))
           (define (kernel-result-character index)
             (result-character kernel index))

           (expose kernel-input-begin "kernel_input_begin")
           (expose kernel-input-character "kernel_input_character")
           (expose kernel-evaluate "kernel_evaluate")
           (expose kernel-names "kernel_names")
           (expose kernel-result-length "kernel_result_length")
           (expose kernel-result-character "kernel_result_character")))))

    ))
