;; These are explicit unsupported external-reader cases, not passing probes.
;; The shared SFIR reader rejects datum labels before interpreter evaluation.
((let ((x '(#1=(a b) #1#))) (eq? (car x) (cadr x))) #t)
((let ((x '#2=(a . #2#))) (eq? x (cdr x))) #t)
