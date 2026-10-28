;; A compiler running as Wasm supplies immutable artifact inputs. Its
;; output exercises both static linking and cached per-library emission.
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (snail shell compiler)
 (snail shell compiler inputs)
 (snail shell compiler session)
 (prefix (snail shell compiler read) reader:)
 (prefix (snail shell syntax) generated:))

(: inputs (-> Bytes Inputs))
(define (inputs client)
  (supply-artifact (supply-artifact no-inputs "client" (list (Pair "client.dat" client)))
                   "admin" (list (Pair "admin.dat" #u8(99)))))

(: generate (-> (List String) (List reader:Syntax) Bytes))
(define (generate loading forms)
  (generated:syntax->bytes
   (generated:library-syntax
    (list "generated" "assets")
    (list "generated-bundle")
    (list (list "snail" "core" "base") (list "snail" "shell" "artifact"))
    (list (generated:form ":"
                          (list (generated:SymbolSyntax "generated-bundle")
                                (generated:SymbolSyntax "ArtifactBundle")))
          (generated:form "define" (list (generated:SymbolSyntax "generated-bundle")
                                         (generated:form "artifact-bundle"
                                                         (list
                                                          (generated:StringSyntax "client")))))))))

(: write-build (-> String (List Built) Unit ! fs))
(define (write-build output built)
  (for-each (lambda (module)
              (write-file (string-append output "/" (Built-name module) ".wat")
                          (Built-text module)))
            built)
  (write-file (string-append output "/modules") (string-join (map Built-name built) "\n"))
  (write-file (string-append output "/compiled")
              (string-join (map Built-name (filter Built-compiled? built)) "\n")))

(match (command-line)
  ((Cons _ (Cons source (Cons output directories)))
   (write-file (string-append output "/program.wat")
               (WholeProgram-text (source->wat directories source generate (inputs #u8(65 0 255)))))
   (let* ((first (build-session (make-session directories) source generate (inputs #u8(65 0 255))))
          (unchanged (build-session (Pair-second first) source generate (inputs #u8(65 0 255)))))
     (write-build (string-append output "/first") (Pair-first first))
     (write-build (string-append output "/unchanged") (Pair-first unchanged))
     (write-build (string-append output "/changed")
                  (Pair-first (build-session (Pair-second unchanged)
                                             source
                                             generate
                                             (inputs #u8(90 0 255)))))))
  (_ (panic "usage: compiler SOURCE OUTPUT LIBRARY ...")))
