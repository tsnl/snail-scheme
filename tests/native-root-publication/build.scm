;; Direct datum lowering preserves the operand roots used by the native checks.
(import
 (scheme base)
 (scheme cxr)
 (scheme file)
 (scheme read)
 (scheme process-context)
 (native llvm)
 (native wasm)
 (native wasm-optimize)
 (native chromium-trace))

(define root (cadr (command-line)))
(define prefix (string-append (caddr (command-line)) "/root-publication"))
(define datum
  (call-with-input-file (string-append root "/tests/native-root-publication/module.scm") read))

(with-chromium-trace-to
 (string-append prefix ".trace.json")
 (lambda ()
   (parameterize ((current-native-imports
                   '((("probe" "collect") "root_publication_collect" () (i32))
                     (("probe" "collect-two") "root_publication_collect_two" () ()))))
     (wasm->llvm-file datum (string-append prefix ".ll"))
     (parameterize ((current-native-gc-stress #t))
       (wasm->llvm-file datum (string-append prefix "-stress.ll"))))
   (call-with-output-file (string-append prefix ".wat") (lambda (port) (write-wasm datum port)))
   (assemble-wasm (string-append prefix ".wat") (string-append prefix ".wasm"))
   (optimize-wasm (string-append prefix ".wasm") (string-append prefix ".opt.wasm"))))
