;; Intermediate diagnostics only: the original repetition count is not run.
;; The complete Compiler benchmark and its expected assembly predicate are separate.
(let* ((count (read))
       (expression (read))
       (target-name (read))
       (option (read))
       (expected (read)))
  (ptree.begin! #f)
  (virtual.begin!)
  (select-target! target-name #f)
  (parse-program
   (list (expression->source expression #f))
   (make-global-environment)
   "program"
   (lambda (lst env c-intf)
     (parameterize ((print-extended-identifiers #t))
       (write
        (map
         (lambda (x)
           (parse-tree->expression
            (case '@STAGE@
              ((raw) (car x))
              ((partial)
               (let ((node (car x)))
                 (if (def? node)
                     (begin
                       (node-children-set!
                        node (list (partial-evaluate (def-val node))))
                       node)
                     (partial-evaluate node))))
              ((normalized) (normalize-parse-tree (car x) (cdr x))))))
         lst))
       (newline)))))
