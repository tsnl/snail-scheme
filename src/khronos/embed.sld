;; The producer of (khronos samples): it lists the sample models and
;; environments `scripts/fetch-khronos-samples` placed beside it and links
;; every file, so a program that imports the library ships them all and
;; reads only those it asks for (`link-file` in (snail shell resource)).
;; Paths are read from the repository's root, where a producer runs, and
;; linked relative to the recipe, src/khronos/.
(define-library (khronos embed)
  (export
   samples-library)
  (import
   (snail core base)
   (snail core io)
   (snail shell syntax))
  (begin

    (define root (→ String) "src/khronos/")

    ;; The library `name`, exporting
    ;;
    ;;   (sample-models)        every model's name
    ;;   (sample-model NAME)    its glTF/ files, each a path within glTF/
    ;;                          and the Resource of the file, its .gltf
    ;;                          first; empty for any other name
    ;;   (sample-environments)  every environment's name
    ;;   (sample-environment NAME)  its HDR file
    (define (samples-library (name (List String))) (→ Syntax) (! fs)
      (let ((models (models-with-gltf)) (environments (environment-names)))
        (library-syntax name
                        (list "sample-models"
                              "sample-model"
                              "sample-environments"
                              "sample-environment")
                        (list (list "snail" "core" "base") (list "snail" "shell" "resource"))
                        (list (names-definition "sample-models" models)
                              (lookup-definition "sample-model"
                                                 (form "List"
                                                       (list (form "Pair"
                                                                   (list (SymbolSyntax "String")
                                                                         (SymbolSyntax
                                                                          "Resource")))))
                                                 (map (lambda (model)
                                                        (new Pair
                                                          (first model)
                                                          (second (model-files model))))
                                                      models)
                                                 (form "Nil" (Nil)))
                              (names-definition "sample-environments" environments)
                              (lookup-definition "sample-environment"
                                                 (form "Option" (list (SymbolSyntax "Resource")))
                                                 (map (lambda (environment)
                                                        (new Pair
                                                          (first environment)
                                                          (second (form "Some"
                                                                        (list
                                                                         (linked (string-append
                                                                                  "environments/"
                                                                                  (string-append
                                                                                   environment
                                                                                   ".hdr"))))))))
                                                      environments)
                                                 (form "None" (Nil)))))))

    ;; ---- Listing ----

    (define (listed (path String)) (→ (List String)) (! fs)
      (match (list-directory (string-append root path))
        ((Ok names) (list-sort string<? names))
        ((Err _) (Nil))))

    (define (kind-of (path String)) (→ (Option FileKind)) (! fs)
      (match (followed-status (string-append root path))
        ((Ok status) (Some (● status kind)))
        ((Err _) (None))))

    (define (directory? (path String)) (→ Bool) (! fs)
      (match (kind-of path)
        ((Some (Directory)) #t)
        (_ #f)))

    (define (models-with-gltf) (→ (List String)) (! fs)
      (filter (lambda (model) (directory? (string-append "models/" (string-append model "/glTF"))))
              (listed "models")))

    (define (environment-names) (→ (List String)) (! fs)
      (map (lambda (file) (substring file 0 (- (string-length file) 4)))
           (filter (lambda (file) (ends-with? file ".hdr")) (listed "environments"))))

    (define (ends-with? (text String) (suffix String)) (→ Bool)
      (and (>= (string-length text) (string-length suffix))
           (string=?
            (substring text (- (string-length text) (string-length suffix)) (string-length text))
            suffix)))

    ;; Every file under `path`, relative to it.
    (define (files-under (path String)) (→ (List String)) (! fs)
      (concatenate (map (lambda (name)
                          (let ((inner (string-append path (string-append "/" name))))
                            (if (directory? inner)
                                (map (lambda (file) (string-append name (string-append "/" file)))
                                     (files-under inner))
                                (list name))))
                        (listed path))))

    ;; `(list (new Pair (first "PATH") (second (link-file "models/MODEL/glTF/PATH"))) ...)`,
    ;; the .gltf files first.
    (define (model-files (model String)) (→ Syntax) (! fs)
      (let* ((directory (string-append "models/" (string-append model "/glTF")))
             (files (files-under directory))
             (ordered (append (filter (lambda (file) (ends-with? file ".gltf")) files)
                              (filter (lambda (file) (not (ends-with? file ".gltf"))) files))))
        (form "list"
              (map (lambda (file)
                     (form "new"
                           (list (SymbolSyntax "Pair")
                                 (form "first" (list (StringSyntax file)))
                                 (form "second"
                                       (list (linked (string-append directory
                                                                    (string-append "/" file))))))))
                   ordered))))

    (define (linked (path String)) (→ Syntax) (form "link-file" (list (StringSyntax path))))

    ;; ---- Definitions ----

    (define (names-definition (name String) (names (List String))) (→ Syntax)
      (form "define"
            (list (form name (Nil))
                  (form "→" (list (form "List" (list (SymbolSyntax "String")))))
                  (form "list" (map StringSyntax names)))))

    ;; `(define (NAME (key String)) (→ RESULT) (cond ((string=? key "K") VALUE) ... (else FALLBACK)))`.
    (define (lookup-definition (name String)
                               (result Syntax)
                               (entries (List (Pair String Syntax)))
                               (fallback Syntax))
      (→ Syntax)
      (form "define"
            (list (form name (list (form "key" (list (SymbolSyntax "String")))))
                  (form "→" (list result))
                  (form "cond"
                        (append (map (lambda (entry)
                                       (ListSyntax (list (form "string=?"
                                                               (list (SymbolSyntax "key")
                                                                     (StringSyntax
                                                                      (● entry first))))
                                                         (● entry second))))
                                     entries)
                                (list (form "else" (list fallback))))))))

    ))
