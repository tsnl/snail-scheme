;; Files embedded from a named project build. The compiler resolves the
;; request while expanding the macro; running a program never builds files
;; or looks up a mutable output directory.
(define-library (snail-core artifact)
  (export
   ArtifactFile
   ArtifactFile-path
   ArtifactFile-bytes
   ArtifactBundle
   ArtifactBundle-files
   artifact-bundle
   artifact-ref)
  (import
   (snail-core base)
   (only (snail-core core) artifact-files))
  (begin

    (struct ArtifactFile
      ((path String)
       (bytes Bytes)))

    (struct ArtifactBundle
      ((files (List ArtifactFile))))

    ;; Constructor identifiers keep their definition scope when imported
    ;; under another name or expanded beneath shadowing local bindings.
    (define-syntax artifact-bundle
      (syntax-rules ()
        ((_ name) (ArtifactBundle (artifact-files name ArtifactFile Cons Nil)))))

    (: artifact-ref (-> ArtifactBundle String (Option Bytes)))
    (define (artifact-ref bundle path)
      (match (find (lambda (file) (string=? (ArtifactFile-path file) path)) (ArtifactBundle-files bundle))
        ((Some file) (Some (ArtifactFile-bytes file)))
        ((None) (None))))

    ))
