;; A host primitive failure must escape this compiler-only abort protocol.
(if (compiler-with-exception-handling
      (lambda () (datum-fail "compiler probe ordinary host failure")))
    42 0)
