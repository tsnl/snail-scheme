(library (snail shell compiler constant-scalars)
  (export read-real
          round-single
          real-bits
          bits-real
          single-bits
          bits-single
          integer-real
          real-integer)
  (import
   (chezscheme)
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
  (define (real-integer value) (exact (truncate value))))
