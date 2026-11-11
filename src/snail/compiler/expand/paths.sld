;; The two paths a body writes as text, which the reader leaves whole: a
;; field path, the identifier `::a::b`, whose labels are its fields in
;; order; and the path of a linked file, the string `"data/x.png"`, whose
;; canonical names are where the file is beside the library. Each is
;; decided here from its text, as the old expander decides it, with what
;; to say of a path that is not one.
(define-library (snail compiler expand paths)
  (export
   FieldPath
   NotAPath
   PathLabels
   EmptyLabel
   field-path
   LinkedPath
   LinkedNames
   UnlinkablePath
   linked-path)
  (import
   (snail core base))
  (begin

    ;; ---- Field paths ----

    ;; An identifier is a path when it starts with `::` and more follows;
    ;; each label between `::`s must have a character.
    (enum FieldPath
      (NotAPath)
      (PathLabels
       ((labels (List String))))
      (EmptyLabel
       ((message String))))

    (: field-path (impl (Fn String -> FieldPath)))
    (define (field-path name)
      (if (and (> (string-length name) 2) (string=? (substring name 0 2) "::"))
          (path-labels name (string->vector name) 2 2 (Nil))
          (NotAPath)))

    (: empty-label (impl (Fn String -> FieldPath)))
    (define (empty-label name)
      (EmptyLabel (string-append "empty field label in " name)))

    ;; The labels of `name` from `start`, where the label being read began,
    ;; with `index` the character being looked at.
    (: path-labels (impl (Fn String (Vector Char) I64 I64 (List String) -> FieldPath)))
    (define (path-labels name chars start index labels)
      (let ((end (vector-length chars)))
        (cond ((= index end)
               (if (= start end)
                   (empty-label name)
                   (PathLabels (reverse (Cons (substring name start end) labels)))))
              ((and (char=? (vector-ref chars index) #\:)
                    (< (+ index 1) end)
                    (char=? (vector-ref chars (+ index 1)) #\:))
               (if (= start index)
                   (empty-label name)
                   (path-labels name
                                chars
                                (+ index 2)
                                (+ index 2)
                                (Cons (substring name start index) labels))))
              (else (path-labels name chars start (+ index 1) labels)))))

    ;; ---- Linked files ----

    ;; A linked path's names, separated by `/`, where `.` is the directory
    ;; it is in and `..` its parent, so `data/../pixel.png` is `pixel.png`.
    ;; A path that is absolute or has an empty name, that names nothing, or
    ;; that climbs out of the directory names no file the payload can ship
    ;; under a name of its own; the first problem met, in order, decides.
    (enum LinkedPath
      (LinkedNames
       ((names (List String))))
      (UnlinkablePath
       ((message String))))

    (: linked-path (impl (Fn String -> LinkedPath)))
    (define (linked-path path)
      (let loop ((names (path-names path))
                 (kept (Nil)))
        (match names
          ((Nil)
           (if (null? kept)
               (UnlinkablePath (string-append "link-file names no file: " path))
               (LinkedNames (reverse kept))))
          ((Cons "." rest) (loop rest kept))
          ((Cons ".." rest)
           (match kept
             ((Cons _ parent) (loop rest parent))
             ((Nil)
              (UnlinkablePath (string-append "link-file may not leave the library's directory: "
                                             path)))))
          ((Cons "" _)
           (UnlinkablePath
            (string-append "link-file takes a path relative to the library, with no empty names: "
                           path)))
          ((Cons name rest) (loop rest (Cons name kept))))))

    (: path-names (impl (Fn String -> (List String))))
    (define (path-names path)
      (match (string-index path #\/)
        ((Some index)
         (Cons (substring path 0 index)
               (path-names (substring path (+ index 1) (string-length path)))))
        ((None) (list path))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-paths)
    (import
     (snail stage0 testing))
    (begin
      (define (test-paths)
        (test-field-paths)
        (test-linked-paths))

      (define (test-field-paths)
        (expect (field-path "::a") (PathLabels (list "a")))
        (expect (field-path "::count::x") (PathLabels (list "count" "x")))
        (expect (field-path "x") (NotAPath))
        (expect (field-path "::") (NotAPath))
        (expect (field-path ":a") (NotAPath))
        (expect (field-path "::a::") (EmptyLabel "empty field label in ::a::"))
        (expect (field-path "::::a") (EmptyLabel "empty field label in ::::a"))
        (expect (field-path "::a:b") (PathLabels (list "a:b")))
        (expect (field-path ":::a") (PathLabels (list ":a"))))

      (define (test-linked-paths)
        (expect (linked-path "pixel.png") (LinkedNames (list "pixel.png")))
        (expect (linked-path "data/./x/../pixel.bin") (LinkedNames (list "data" "pixel.bin")))
        (expect (linked-path "a/..") (UnlinkablePath "link-file names no file: a/.."))
        (expect (linked-path ".") (UnlinkablePath "link-file names no file: ."))
        (expect (linked-path "../x")
                (UnlinkablePath "link-file may not leave the library's directory: ../x"))
        (expect (linked-path "/abs")
                (UnlinkablePath
                 (string-append
                  "link-file takes a path relative to the library, with no empty names: "
                  "/abs")))
        (expect (linked-path "a//b")
                (UnlinkablePath
                 (string-append
                  "link-file takes a path relative to the library, with no empty names: "
                  "a//b")))
        (expect (linked-path "")
                (UnlinkablePath
                 (string-append
                  "link-file takes a path relative to the library, with no empty names: "
                  "")))
        (expect (linked-path "a/../../b")
                (UnlinkablePath "link-file may not leave the library's directory: a/../../b")))))
   (else)))
