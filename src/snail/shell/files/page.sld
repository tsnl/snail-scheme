;; The page's file pickers and drops for the `files` effect:
;; `with-page-files` binds each operation to the browser host
;; (host/browser/files.mjs).
(define-library (snail shell files page)
  (export
   with-page-files)
  (import
   (snail core base)
   (prefix (snail runtime browser files) host-)
   (snail shell files))
  (begin

    ;; ---- Handling ----

    (define (with-page-files (work (Fn → T ! files e))) (→ T) (! e) (∀ (T e))
      (handle files
          ((open-picker (lambda (choice)
                          (host-open-picker (match choice
                                              ((SomeFiles) 0)
                                              ((Folder) 1)))))
           (chosen-files page-chosen))
        (work)))

    ;; The listing is each file's path and address, a NUL after each,
    ;; read as fields from the last back to the first.

    (define (page-chosen) (→ (List Chosen))
      (pairs (map list->string
                  (fold-right (lambda (index fields)
                                (let ((scalar (host-reply-scalar (i64->i32 index))))
                                  (match fields
                                    ((Cons field rest)
                                     (if (= scalar 0)
                                         (Cons (Nil) fields)
                                         (Cons (Cons (integer->char (i32->i64 scalar)) field)
                                               rest)))
                                    ((Nil) fields))))
                              (list (Nil))
                              (iota (i32->i64 (host-listing)))))))

    (define (pairs (fields (List String))) (→ (List Chosen))
      (match fields
        ((Cons path (Cons address rest))
         (Cons (new Chosen (path path) (address address)) (pairs rest)))
        (_ (Nil))))

    ))
