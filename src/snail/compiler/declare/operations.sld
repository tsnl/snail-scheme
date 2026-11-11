;; What an operation's type says, as the old compiler's
;; `declare-operation-type` (src/snail/shell/compiler/expand.sld) reads
;; it: an operation is a function, whose arrow's effects are a closed row,
;; its latent effects, which its implementations may perform where it is
;; performed. Its own effect is implied, never written. Its scheme is
;; operational, so a callable or code there is the arrow it holds.
(define-library (snail compiler declare operations)
  (export
   OperationType
   operation-type)
  (import
   (snail core base)
   (only (snail compiler expand language) Global)
   (snail compiler declare language))
  (begin

    ;; ---- Operations ----

    (struct OperationType
      ((parameters (List Type))
       (result Type)
       (latent (List Global))))

    ;; The parameters, result and latent effects of an operation whose
    ;; operational scheme is `scheme`, or the old compiler's refusal of a
    ;; type that is no function, or whose row is open.
    (: operation-type (impl (Fn Scheme -> (Result OperationType String))))
    (define (operation-type scheme)
      (match (::type scheme)
        ((Callable _ _ arrow)
         (match (::tail (::effects arrow))
           ((None)
            (Ok (OperationType (::parameters arrow) (::result arrow) (::labels (::effects arrow)))))
           ((Some _) (Err closed-function))))
        (_ (Err closed-function))))

    (: closed-function String)
    (define closed-function
      "an operation has a function type with a closed row; its effect is implied")

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-operations)
    (import
     (only (snail compiler expand language) Dyn FnContract)
     (snail stage0 testing))
    (begin
      (define (test-operations)
        (let* ((i64 (Con (Global (list "snail" "core" "forms") "I64" 0) (list)))
               (log (Global (list "main") "log" 0))
               (function (lambda (effects)
                           (Scheme (list)
                                   (list)
                                   (list)
                                   (Callable (Dyn) (FnContract) (Arrow (list i64) i64 effects))))))
          (expect (operation-type (function (Effects (list log) (None))))
                  (Ok (OperationType (list i64) i64 (list log))))
          (expect (operation-type (function (Effects (list) (Some (Var (Written "e"))))))
                  (Err "an operation has a function type with a closed row; its effect is implied"))
          (expect (operation-type (Scheme (list) (list) (list) i64))
                  (Err
                   "an operation has a function type with a closed row; its effect is implied"))))))
   (else)))
