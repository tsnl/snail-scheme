(import
 (lofi primitive))
(def identity (syntax-rules () ((_ value) value)))
(def answer (-> I32) (lambda () (identity 42)))
(answer)
