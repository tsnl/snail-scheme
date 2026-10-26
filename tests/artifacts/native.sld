(import
 (lofi base)
 (lofi io)
 (lofi artifact))

(define bundle (artifact-bundle "client"))
(for-each (lambda (file)
            (display (ArtifactFile-path file))
            (display ":")
            (vector-for-each (lambda (byte) (display (u8->i32 byte)) (display ",")) (ArtifactFile-bytes file))
            (newline))
          (ArtifactBundle-files bundle))
