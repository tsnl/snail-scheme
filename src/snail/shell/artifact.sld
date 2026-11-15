;; Files embedded from a named project build. The compiler resolves the
;; request while expanding the macro; running a program never builds files
;; or looks up a mutable output directory.
(define-library (snail shell artifact)
  (export
   Artifact-file
   Artifact-bundle
   artifact-bundle
   artifact-ref)
  (import
   (snail core base)
   (only (snail core forms) artifact-files))
  (begin

    (record Artifact-file
      ((path String)
       (bytes Bytes)))

    (record Artifact-bundle
      ((files (List Artifact-file))))

    ;; Constructor identifiers keep their definition scope when imported
    ;; under another name or expanded beneath shadowing local bindings.
    (define-syntax artifact-bundle
      (syntax-rules ()
        ((_ name)
         (new Artifact-bundle
           (files (artifact-files name
                                  (lambda (path bytes)
                                    (new Artifact-file (path path) (bytes bytes)))
                                  Cons
                                  Nil))))))

    (define (artifact-ref (bundle Artifact-bundle) (path String)) (→ (Option Bytes))
      (match (find (lambda (file) (string=? (● file path) path))
                   (● bundle files))
        ((Some file) (Some (● file bytes)))
        ((None) (None))))

    ))
