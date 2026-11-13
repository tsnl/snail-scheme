;; Files embedded from a named project build. The compiler resolves the
;; request while expanding the macro; running a program never builds files
;; or looks up a mutable output directory.
(define-library (snail shell artifact)
  (export
   ArtifactFile
   ArtifactBundle
   artifact-bundle
   artifact-ref)
  (import
   (snail core base)
   (only (snail core forms) artifact-files))
  (begin

    (record ArtifactFile
      ((path String)
       (bytes Bytes)))

    (record ArtifactBundle
      ((files (List ArtifactFile))))

    ;; Constructor identifiers keep their definition scope when imported
    ;; under another name or expanded beneath shadowing local bindings.
    (define-syntax artifact-bundle
      (syntax-rules ()
        ((_ name)
         (new ArtifactBundle
           (files (artifact-files name
                                  (lambda (path bytes)
                                    (new ArtifactFile (path path) (bytes bytes)))
                                  Cons
                                  Nil))))))

    (define (artifact-ref (bundle ArtifactBundle) (path String)) (→ (Option Bytes))
      (match (find (lambda (file) (string=? (● file path) path))
                   (● bundle files))
        ((Some file) (Some (● file bytes)))
        ((None) (None))))

    ))
