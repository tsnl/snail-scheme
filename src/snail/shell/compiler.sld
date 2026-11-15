;; The compiler's passes in order, from a program's source path to
;; WebAssembly text. Every invocation reads, checks and emits the whole
;; program afresh. The typed driver serves
;; both compiler entries: Chez runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (snail shell compiler)
  (export
   WholeProgram
   source->wat
   Checked
   source->checked
   checked->modules
   source->modules
   Built
   LinkedFile
   no-inputs)
  (import
   (snail core base)
   (snail core io)
   (snail shell compiler read)
   (only (snail shell compiler inputs) Inputs no-inputs)
   (snail shell compiler core)
   (snail shell compiler expand)
   (snail shell compiler check)
   (snail shell compiler prepare)
   (only (snail shell compiler specialize) control-effects prepare-specialization)
   (snail shell compiler wasm))
  (begin

    ;; The front of every compile: the program a source path reads, expanded.
    ;; `generate` runs the producer program of a `generate-library`, given
    ;; the libraries loading when it was reached, and returns the bytes of
    ;; the syntax it writes.

    (define (source->expanded (directories (List String))
                              (source String)
                              (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                              (inputs Inputs)
                              (target (Option (List String))))
      (→ ExpandedProgram)
      (! fs compile)
      (expand-program directories generate inputs target source))

    ;; A program compiled to one module: its text, and the files it links,
    ;; which ship beside it.
    (record Built
      ((name String)
       (text String)
       (links (List LinkedFile))))

    (record WholeProgram
      ((text String)
       (links (List LinkedFile))))

    (define (source->wat (directories (List String))
                         (source String)
                         (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                         (inputs Inputs)
                         (target (Option (List String))))
      (→ WholeProgram)
      (! mut fs compile)
      (let* ((expanded (source->expanded directories source generate inputs target))
             (typed (check-program (● expanded program)))
             (module (emit-module (prepare-program typed))))
        (new WholeProgram (text (wat->string module)) (links (program-links expanded)))))

    ;; A program read, expanded and checked, before anything is emitted: what
    ;; a development build compiles each library from, and what an editor
    ;; asks of the program's names (snail shell lsp).
    (record Checked
      ((expanded ExpandedProgram)
       (typed Typed)))

    (define (source->checked (directories (List String))
                             (source String)
                             (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                             (inputs Inputs)
                             (target (Option (List String))))
      (→ Checked)
      (! fs compile)
      (let ((expanded (source->expanded directories source generate inputs target)))
        (new Checked (expanded expanded) (typed (check-program (● expanded program))))))

    ;; One module of text per library, and one for the program, in program
    ;; order: each comes after the modules it imports from, with the files
    ;; its library links. Every library is checked and emitted in this build.

    (define (source->modules (directories (List String))
                             (source String)
                             (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                             (inputs Inputs)
                             (target (Option (List String))))
      (→ (List Built))
      (! mut fs compile)
      (checked->modules (source->checked directories source generate inputs target)))

    (define (checked->modules (checked Checked)) (→ (List Built)) (! mut compile)
      (let* ((expanded (● checked expanded))
             (typed (● checked typed))
             (input (prepare-specialization typed)))
        (append (if (null? (control-effects (● typed program))) (Nil)
                    (list (new Built (name "snail.core.control")
                               (text (wat->string (emit-control-module (● typed program))))
                               (links (Nil)))))
                (map (lambda (library)
                       (new Built (name (● library first))
                            (text (wat->string (emit-module (prepare-library input (● library first)
                                                                             (● library second)))))
                            (links (library-links expanded (● library first)))))
                     (filter (lambda (library) (not (null? (● library second))))
                             (library-items (● typed program) (● typed items)))))))

    ))
