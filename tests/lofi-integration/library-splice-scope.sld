(import
 (lofi core)
 (only (lofi primitive) i32-add))
(emit answer)
(begin
 (define-syntax emit (syntax-rules () ((_ name) (def name 40))))
 (begin
  (let amount 1)
  (define-syntax captured (syntax-rules () ((_) (i32-add amount 1))))))
(let amount 100)
(i32-add answer (captured))
