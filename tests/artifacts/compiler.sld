;; A compiler running as Wasm supplies a concrete artifact resolver. Its
;; output exercises both static linking and cached per-library emission.
(import
 (lofi base)
 (lofi io)
 (lofi compiler)
 (lofi compiler session)
 (prefix (lofi compiler read) reader:)
 (prefix (lofi syntax) generated:))

(: client-bytes (Ref Bytes))
(define client-bytes (ref #u8(65 0 255)))

(: requests (Ref (List String)))
(define requests (ref (Nil)))

(: resolve-artifact (-> String reader:Loc (List (Pair String Bytes)) ! mut fs))
(define (resolve-artifact name loc)
  (ref-set! requests (Cons name (ref-get requests)))
  (cond ((string=? name "client") (list (Pair "client.dat" (ref-get client-bytes))))
        ((string=? name "admin") (list (Pair "admin.dat" #u8(99))))
        (else (reader:compile-error loc (string-append "unexpected artifact request: " name)))))

(: generate (-> (List reader:Syntax) Bytes ! mut fs))
(define (generate forms)
  (generated:syntax->bytes
   (generated:library-syntax
    (list "generated" "assets") (list "generated-bundle") (list (list "lofi" "base") (list "lofi" "artifact"))
    (list (generated:form ":" (list (generated:SymbolSyntax "generated-bundle") (generated:SymbolSyntax "ArtifactBundle")))
          (generated:form "define" (list (generated:SymbolSyntax "generated-bundle")
                                         (generated:form "artifact-bundle" (list (generated:StringSyntax "client")))))))))

(: write-build (-> String (List Built) Unit ! fs))
(define (write-build output built)
  (for-each (lambda (module) (write-file (string-append output "/" (Built-name module) ".wat") (Built-text module))) built)
  (write-file (string-append output "/modules") (string-join (map Built-name built) "\n"))
  (write-file (string-append output "/compiled") (string-join (map Built-name (filter Built-compiled? built)) "\n")))

(match (command-line)
  ((Cons _ (Cons source (Cons output directories)))
   (write-file (string-append output "/program.wat") (compile->wat directories source generate resolve-artifact))
   (let* ((first (build-session (make-session directories generate resolve-artifact) source))
          (unchanged (begin (ref-set! requests (Nil)) (build-session (Pair-second first) source))))
     (write-build (string-append output "/first") (Pair-first first))
     (write-build (string-append output "/unchanged") (Pair-first unchanged))
     (write-file (string-append output "/unchanged/requests") (string-join (ref-get requests) "\n"))
     (ref-set! client-bytes #u8(90 0 255))
     (write-build (string-append output "/changed") (Pair-first (build-session (Pair-second unchanged) source)))))
  (_ (panic "usage: compiler SOURCE OUTPUT LIBRARY ...")))
