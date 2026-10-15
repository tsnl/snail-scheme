;; Static tensor operations have two concrete language representations. Eager
;; operations enter unboxed kernels; symbolic operations allocate Scheme graphs.
(define-library (snail-scheme iverson-typed)
  (export TensorOperations <immediate-tensor> <symbolic-tensor>
          tensor immediate-values symbolic-input symbolic-constant symbolic->datum evaluate
          tensor-add tensor-mul tensor-transpose tensor-sum tensor-matmul tensor-square tensor-gram)
  (import (scheme base) (snail typing)
          (prefix (snail-scheme iverson-ghost) raw:))
  (begin

    ;; ---- Carrier types and interface ----

    (define-record-type <immediate-tensor>
      (immediate value) immediate?
      (value : Any immediate-value))
    (define-record-type <symbolic-tensor>
      (symbolic operation operands) symbolic?
      (operation : Symbol symbolic-operation)
      (operands : Pair symbolic-operands))

    (define-class (TensorOperations T)
      (: tensor-add (-> T T T))
      (: tensor-mul (-> T T T))
      (: tensor-transpose (-> T T))
      (: tensor-sum (-> T T))
      (: tensor-matmul (-> T T T)))

    (: tensor (-> Any Any Symbol <immediate-tensor>))
    (define (tensor dimensions elements dtype)
      (immediate (raw:array dimensions elements dtype)))

    (: immediate-values (-> <immediate-tensor> Vector))
    (define (immediate-values value) (raw:array->vector (immediate-value value)))

    ;; ---- Eager instance ----

    (define-instance (TensorOperations <immediate-tensor>)
      (tensor-add (lambda (a b) (immediate (raw:add (immediate-value a) (immediate-value b)))))
      (tensor-mul (lambda (a b) (immediate (raw:mul (immediate-value a) (immediate-value b)))))
      (tensor-transpose (lambda (a) (immediate (raw:transpose (immediate-value a)))))
      (tensor-sum (lambda (a) (immediate (raw:sum (immediate-value a)))))
      (tensor-matmul (lambda (a b) (immediate (raw:matmul (immediate-value a) (immediate-value b))))))

    ;; ---- Symbolic instance ----

    (: symbolic-input (-> Symbol <symbolic-tensor>))
    (define (symbolic-input name) (symbolic 'input (list name)))
    (: symbolic-constant (-> <immediate-tensor> <symbolic-tensor>))
    (define (symbolic-constant value) (symbolic 'constant (list value)))

    (define-instance (TensorOperations <symbolic-tensor>)
      (tensor-add (lambda (a b) (symbolic 'add (list a b))))
      (tensor-mul (lambda (a b) (symbolic 'mul (list a b))))
      (tensor-transpose (lambda (a) (symbolic 'transpose (list a))))
      (tensor-sum (lambda (a) (symbolic 'sum (list a))))
      (tensor-matmul (lambda (a b) (symbolic 'matmul (list a b)))))

    ;; ---- Shared algorithms ----

    (: tensor-square (All (T) (=> ((TensorOperations T)) (-> T T))))
    (define (tensor-square x) (tensor-mul x x))
    (: tensor-gram (All (T) (=> ((TensorOperations T)) (-> T T))))
    (define (tensor-gram x) (tensor-matmul (tensor-transpose x) x))

    ;; ---- Interpreting symbolic graphs on concrete values ----

    ;; The environment callback supplies concrete inputs. Its return is checked
    ;; against the chosen carrier; the callback never selects a typeclass instance.
    (: evaluate (-> <symbolic-tensor> Procedure <immediate-tensor>))
    (define (evaluate value lookup)
      (let ((operands (symbolic-operands value)))
        (case (symbolic-operation value)
          ((input) (ann (lookup (car operands)) <immediate-tensor>))
          ((constant) (ann (car operands) <immediate-tensor>))
          ((add) (tensor-add (evaluate (ann (car operands) <symbolic-tensor>) lookup)
                             (evaluate (ann (cadr operands) <symbolic-tensor>) lookup)))
          ((mul) (tensor-mul (evaluate (ann (car operands) <symbolic-tensor>) lookup)
                             (evaluate (ann (cadr operands) <symbolic-tensor>) lookup)))
          ((matmul) (tensor-matmul (evaluate (ann (car operands) <symbolic-tensor>) lookup)
                                   (evaluate (ann (cadr operands) <symbolic-tensor>) lookup)))
          ((transpose) (tensor-transpose (evaluate (ann (car operands) <symbolic-tensor>) lookup)))
          ((sum) (tensor-sum (evaluate (ann (car operands) <symbolic-tensor>) lookup)))
          (else (error "unknown symbolic tensor operation" (symbolic-operation value))))))

    (: symbolic->datum (-> <symbolic-tensor> Any))
    (define (symbolic->datum value)
      (let ((operands (symbolic-operands value)))
        (case (symbolic-operation value)
          ((input) (car operands))
          ((constant) (list 'constant (immediate-values (ann (car operands) <immediate-tensor>))))
          (else (cons (symbolic-operation value)
                      (map (lambda (operand) (symbolic->datum (ann operand <symbolic-tensor>))) operands))))))))
