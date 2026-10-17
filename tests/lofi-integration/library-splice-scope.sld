(import
 (lofi core)
 (only (lofi primitive) i32-add))
(emit answer)
(library-begin
 (def emit (syntax-rules () ((_ name) (def name 40))))
 (library-begin
  (let amount 1)
  (def captured (syntax-rules () ((_) (i32-add amount 1))))))
(let amount 100)
(i32-add answer (captured))
