(library (snail shell compiler constant-scalars)
  (export read-real
          round-single
          real-bits
          bits-real
          single-bits
          bits-single
          integer-real
          real-integer
          unicode-scalar
          load-native-scalars!)
  (import
   (chezscheme)
   (snail stage0 system)
   (only (snail core base) Some None))

  (define (read-real text)
    (let ([value (string->number text)])
      (if (and value (real? value)) (Some (inexact value)) (None))))

  (define (round-single value)
    (let ([bytes (make-bytevector 4)])
      (bytevector-ieee-single-native-set! bytes 0 value)
      (bytevector-ieee-single-native-ref bytes 0)))

  (define (real-bits value)
    (let ([bytes (make-bytevector 8)])
      (bytevector-ieee-double-native-set! bytes 0 value)
      (bytevector-s64-native-ref bytes 0)))

  (define (bits-real value)
    (let ([bytes (make-bytevector 8)])
      (bytevector-s64-native-set! bytes 0 value)
      (bytevector-ieee-double-native-ref bytes 0)))

  (define (single-bits value)
    (let ([bytes (make-bytevector 4)])
      (bytevector-ieee-single-native-set! bytes 0 value)
      (bytevector-s32-native-ref bytes 0)))

  (define (bits-single value)
    (let ([bytes (make-bytevector 4)])
      (bytevector-s32-native-set! bytes 0 value)
      (bytevector-ieee-single-native-ref bytes 0)))

  (define (integer-real value) (inexact value))
  (define (real-integer value) (exact (truncate value)))

  ;; Build only the scalar bridge, not the runtime or compiler. Atomic rename
  ;; lets independent compiler invocations share this cache without a partial
  ;; dynamic library ever becoming visible.
  (define (load-native-scalars! root)
    (let* ([directory (make-path root "build/chez-scalars")]
           [output (make-path directory "scalars.so")]
           [source (make-path root "host/chez/scalars.rs")]
           [inputs (list source (make-path root "crates/snail-core-support/src/unicode.rs")
                         (make-path root "rust-toolchain.toml"))])
      (create-directory* directory)
      (when (or (not (file-exists? output))
                (exists (lambda (input) (> (modification-nanoseconds input)
                                           (modification-nanoseconds output))) inputs))
        (let ([temporary (string-append output "." (number->string (get-process-id)))])
          (unless (zero? (run-command-status
                          (list (or (getenv "RUSTC") "rustc")
                                (string-append "+" (pinned-channel root))
                                "--edition=2024" "--crate-type=cdylib" "-O" "-C" "panic=abort"
                                source "-o" temporary)))
            (error 'bootstrap "cannot compile native Unicode scalar services"))
          (rename-file temporary output)))
      (load-shared-object output)))

  (define (unicode-scalar operation code index)
    (cond
     [(string=? operation "snail:text/upcase")
      (Some ((foreign-procedure "snail_bootstrap_upcase" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/downcase")
      (Some ((foreign-procedure "snail_bootstrap_downcase" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/foldcase")
      (Some ((foreign-procedure "snail_bootstrap_foldcase" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/lowercase")
      (Some ((foreign-procedure "snail_bootstrap_lowercase" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/uppercase")
      (Some ((foreign-procedure "snail_bootstrap_uppercase" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/digit-value")
      (Some ((foreign-procedure "snail_bootstrap_digit_value" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/alphabetic")
      (Some ((foreign-procedure "snail_bootstrap_alphabetic" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/numeric")
      (Some ((foreign-procedure "snail_bootstrap_numeric" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:datum/whitespace")
      (Some ((foreign-procedure "snail_bootstrap_whitespace" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/full-fold-length")
      (Some ((foreign-procedure "snail_bootstrap_full_fold_length" (unsigned-32) integer-32) code))]
     [(string=? operation "snail:text/full-fold-scalar")
      (Some
       ((foreign-procedure "snail_bootstrap_full_fold_scalar" (unsigned-32 integer-32) integer-32)
        code
        index))]
     [else (None)]))
  )
