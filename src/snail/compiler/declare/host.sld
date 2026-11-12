;; What a host function may take, as the old compiler's
;; `check-host-parameters` (src/snail/shell/compiler/expand.sld) checks an
;; extern's type. The host reads only scalars, and one String or Bytes
;; argument, which the caller stages in the runtime's buffer just before the
;; call; so a host function may take a buffer only as its last argument.
;; Bytes is `(Vector U8)`, the type its alias stands for.
(define-library (snail compiler declare host)
  (export
   host-problem)
  (import
   (snail core base)
   (snail compiler declare language)
   (snail compiler types type)
   (only (snail compiler names libraries) forms-library)
   (only (snail compiler builtins forms) string-global vector-global u8-global)
   (snail compiler types equality)
   (only (snail compiler names globals) same-global?))
  (begin

    ;; ---- Host functions ----

    ;; `type` is an extern's, executable code's, so a function is a
    ;; Callable. A type that is no function takes nothing.
    (: host-problem (impl (Fn Type -> (Option String))))
    (define (host-problem type)
      (match type
        ((Callable _ _ arrow)
         (if (staged-last? (::parameters arrow))
             (None)
             (Some "a host function can take a String or Bytes only as its last argument")))
        (_ (None))))

    ;; No parameter but the last is a buffer.
    (: staged-last? (impl (Fn (List Type) -> Bool)))
    (define (staged-last? parameters)
      (match parameters
        ((Cons parameter (Cons next rest))
         (and (not (buffer? parameter)) (staged-last? (Cons next rest))))
        (_ #t)))

    (: buffer? (impl (Fn Type -> Bool)))
    (define (buffer? type)
      (match type
        ((Con global (Nil)) (same-global? global string-global))
        ((Con global (Cons (Con element (Nil)) (Nil)))
         (and (same-global? global vector-global) (same-global? element u8-global)))
        (_ #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-host)
    (import
     (only (snail compiler names globals) Global)
     (snail stage0 testing))
    (begin
      (define (test-host)
        (let* ((text (Con string-global (list)))
               (bytes (Con vector-global (list (Con u8-global (list)))))
               (i64 (Con (Global forms-library "I64" 0) (list)))
               (unit-type (Con (Global forms-library "Unit" 0) (list)))
               (host (lambda (parameters)
                       (Callable (Dyn)
                                 (FnContract)
                                 (Arrow parameters unit-type (Effects (list) (None))))))
               (last "a host function can take a String or Bytes only as its last argument"))
          ;; Read off error-host-buffer-position.sld.
          (expect (host-problem (host (list text i64))) (Some last))
          (expect (host-problem (host (list i64 bytes i64))) (Some last))
          (expect (host-problem (host (list i64 text))) (None))
          (expect (host-problem (host (list bytes))) (None))
          (expect (host-problem (host (list))) (None))
          ;; Two buffers: the first is not last.
          (expect (host-problem (host (list text text))) (Some last))
          ;; A Vector of another element, and a String of another library,
          ;; are no buffers.
          (expect (host-problem (host (list (Con vector-global (list i64)) i64))) (None))
          (expect (host-problem (host (list (Con (Global (list "main") "String" 0) (list)) i64)))
                  (None))
          (expect (host-problem i64) (None))))))
   (else)))
