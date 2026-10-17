(import
 (lofi primitive))
(def forward (syntax-rules () ((_ operator arguments) (operator . arguments))))
(forward i32-add (20 22))
