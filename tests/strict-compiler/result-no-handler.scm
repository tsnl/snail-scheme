;; An abort outside the source handler remains a fatal error.
(match (ann (compiler-abort-result) (CompilerResult I64))
  ((compiler-success value) value)
  ((compiler-failure) 0))
