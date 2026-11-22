;; What a producer that embeds a build writes: a library whose accessor
;; links every file of the build's output, by its path there.
(define-library (embedded linking)
  (export
   files-library)
  (import
   (snail core base)
   (snail core io)
   (snail shell syntax))
  (begin

    ;; `(define-library NAME (export ACCESSOR) ... (define (ACCESSOR) (→
    ;; (List (Pair String Resource))) (list (new Pair (first PATH) (second
    ;; (link-file FILE))) ...)))`, one pair for each file under `directory`.

    (define (files-library (fs Fs) (name (List String)) (accessor String) (directory String))
      (→ Syntax)
      (library-syntax name
                      (list accessor)
                      (list (list "snail" "core" "base") (list "snail" "shell" "resource"))
                      (list (form "define"
                                  (list (form accessor (Nil))
                                        (form "→" (list (form "List" (list (pair-type)))))
                                        (form "list"
                                              (map (lambda (path) (file-entry directory path))
                                                   (files-under fs directory ""))))))))

    (define (pair-type) (→ Syntax)
      (form "Pair" (list (SymbolSyntax "String") (SymbolSyntax "Resource"))))

    (define (file-entry (directory String) (path String)) (→ Syntax)
      (form "new"
            (list (SymbolSyntax "Pair")
                  (form "first" (list (StringSyntax path)))
                  (form "second"
                        (list (form "link-file"
                                    (list (StringSyntax (string-append directory "/" path)))))))))

    ;; Every file under `directory`/`prefix`, by its path from `directory`,
    ;; in name order, through directories and the links a build's store
    ;; view holds.

    (define (files-under (fs Fs) (directory String) (prefix String)) (→ (List String))
      (match (list-directory fs (string-append directory "/" prefix))
        ((Ok names)
         (concatenate (map (lambda (name) (file-or-files fs directory (string-append prefix name)))
                           (list-sort string<? names))))
        ((Err _) (panic (string-append "cannot list " directory "/" prefix)))))

    (define (file-or-files (fs Fs) (directory String) (path String)) (→ (List String))
      (match (followed-status fs (string-append directory "/" path))
        ((Ok status)
         (match (● status kind)
           ((Directory) (files-under fs directory (string-append path "/")))
           (_ (list path))))
        ((Err _) (panic (string-append "cannot read " directory "/" path)))))

    ))
