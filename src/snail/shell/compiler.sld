;; The compiler's passes in order, from a program's source path to
;; WebAssembly text. Every invocation reads, checks and emits the whole
;; program afresh. The typed driver serves
;; both compiler entries: Chez runs
;; the source as stage 0, and Node runs the compiler compiled to Wasm.
(define-library (snail shell compiler)
  (export
   WholeProgram
   source->wat
   checked->wat
   Checked
   source->checked
   LinkedFile)
  (import
   (snail core base)
   (snail core io)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler expand)
   (snail shell compiler check)
   (snail shell compiler prepare)
   (snail shell compiler wasm))
  (begin

    ;; The front of every compile: the program a source path reads, expanded.
    ;; `generate` runs the producer program of a `generate-library`, given
    ;; the libraries loading when it was reached, and returns the bytes of
    ;; the syntax it writes.

    (define (source->expanded (directories (List String))
                              (source String)
                              (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                              (target (Option (List String))))
      (→ ExpandedProgram)
      (! fs compile)
      (expand-program directories generate target source))

    ;; A program read, expanded and checked, before anything is emitted: what
    ;; a build emits, and what an editor asks of the program's names (snail
    ;; shell lsp).
    (record Checked
      ((expanded ExpandedProgram)
       (typed Typed)))

    (define (source->checked (directories (List String))
                             (source String)
                             (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                             (target (Option (List String))))
      (→ Checked)
      (! fs compile)
      (let ((expanded (source->expanded directories source generate target)))
        (new Checked (expanded expanded) (typed (check-program (● expanded program))))))

    ;; The whole program as one module: its text, the libraries it holds,
    ;; in program order, and the files it links. A build links it with the
    ;; runtime into a module of its own.
    (record WholeProgram
      ((text String)
       (libraries (List String))
       (links (List LinkedFile))))

    (define (source->wat (directories (List String))
                         (source String)
                         (generate (Fn (List String) (List Syntax) → Bytes ! fs compile))
                         (target (Option (List String))))
      (→ WholeProgram)
      (! mut fs compile)
      (checked->wat (source->checked directories source generate target)))

    (define (checked->wat (checked Checked)) (→ WholeProgram) (! mut compile)
      (let ((expanded (● checked expanded)))
        (new WholeProgram
          (text (wat->string (emit-module (prepare-program (● checked typed)))))
          (libraries (map (lambda (library) (● library first)) (● (● expanded program) libraries)))
          (links (program-links expanded)))))

    ))
