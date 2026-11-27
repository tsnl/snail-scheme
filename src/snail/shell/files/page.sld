;; The page's file pickers and drops as a `FilePicker`:
;; `page-file-picker` binds each operation to the browser host
;; (host/browser/files.mjs).
(define-library (snail shell files page)
  (export
   page-file-picker)
  (import
   (snail core base)
   (only (snail core io) Host OutputPort)
   (snail shell utf8)
   (prefix (snail runtime browser files) host-)
   (snail shell files))
  (begin

    ;; ---- Handling ----

    (define (page-file-picker (host Host)) (→ FilePicker)
      (new FilePicker
        (open-picker (lambda (choice)
                       (host-open-picker (match choice
                                           ((SomeFiles) 0)
                                           ((Folder) 1)))))
        (chosen-files page-chosen)
        (download-text (lambda (name)
                         (let ((id (host-open-download (string->utf8 name))))
                           (new OutputPort
                             (write-string
                              (lambda (text) (host-write-download id (string->utf8 text))))))))))

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
