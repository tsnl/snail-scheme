;; The compiler's intrinsic syntax bindings. This bootstrap manifest names the
;; typed kernel; libraries can rename these forms and define derived languages.
(define-library (lofi core)
  (export def lambda if let begin ann inst match datatype typeclass instance
          define-overload define-extern syntax-rules define-syntax
          : All => -> Ref List Vector Rest Type Constraint Kind-> Evidence
          I32 I64 F32 F64 Bool Char Unit Any Never String Bytevector))
