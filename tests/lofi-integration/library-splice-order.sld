(import
 (rename (lofi core) (library-begin declarations))
 (only (lofi primitive) ref ref-get ref-set! i32-add))
(let trace (ref 0))
(declarations
 (ref-set! trace 10)
 (declarations (ref-set! trace (i32-add (ref-get trace) 20))))
(ref-set! trace (i32-add (ref-get trace) 12))
(ref-get trace)
