# SFIR

SFIR (Snail functional IR, pronounced “sphere”) is a typed functional language
and a reusable compiler target. It keeps functions, algebraic data and generic
definitions intact long enough for the compiler to reason about them. Its
S-expression syntax is small enough to generate and practical to write by hand.

## A first look

Parentheses enclose an operation and its arguments. `def` introduces a binding;
`lambda` constructs a function. Here are two ways to compute Fibonacci numbers:

```scheme
(import (sfir base))

(def fibonacci (-> I32 I32)
  (lambda (n)
    (if (<= n 1)
        n
        (+ (fibonacci (- n 2)) (fibonacci (- n 1))))))

(def fast-fibonacci (-> I32 I32)
  (lambda (n)
    (begin
      (def inner (-> I32 I32 I32 I32)
        (lambda (i previous current)
          (begin
            (let next (+ previous current))
            (if (= i n)
                next
                (inner (+ i 1) current next)))))
      (if (<= n 1) n (inner 2 0 1)))))

(fast-fibonacci 10) ; 55
```

The local function `inner` uses `n` from its enclosing function and calls itself
to continue the calculation. That last call needs no additional return frame:
SFIR requires proper tail recursion. The examples use I32 integers; for
nonnegative inputs through 46, the Fibonacci result fits that type. Later
chapters explain overflow and generic functions.

Types also describe structured values and operations on them. In this example,
a color is either a primary color or three floating-point components. A class
declares an operation; instances provide implementations for particular types.

```scheme
(import (sfir base) (example hex))

(def Vec3
  (datatype (T)
    (vec3 (x T vec3-x) (y T vec3-y) (z T vec3-z))))
(def PrimaryColor (datatype () (red) (green) (blue)))
(def Color
  (datatype ()
    (primary (value PrimaryColor))
    (rgb (value (Vec3 F32)))))

(def ToHexString
  (typeclass (T)
    (: to-hex-string (-> T String))))

(def channel-hex (-> F32 String)
  (lambda (component)
    (byte->hex (f32->i32 (* component (ann 255.0 F32))))))

(def primary-color-to-hex
  (instance (ToHexString PrimaryColor)
    (to-hex-string
      (lambda (color)
        (match color
          ((red) "#ff0000ff")
          ((green) "#00ff00ff")
          ((blue) "#0000ffff"))))))

(def vec3f-to-hex
  (instance (ToHexString (Vec3 F32))
    (to-hex-string
      (lambda (v)
        (string-append "#" (channel-hex (vec3-x v))
                           (channel-hex (vec3-y v))
                           (channel-hex (vec3-z v)) "ff")))))

(def color-to-hex
  (instance (ToHexString Color)
    (to-hex-string
      (lambda (color)
        (match color
          ((primary value) (to-hex-string value))
          ((rgb value) (to-hex-string value)))))))

(to-hex-string (primary (red))) ; "#ff0000ff"
```

`(example hex)` supplies `byte->hex : (-> I32 String)`, which formats an integer
from 0 through 255 as two lowercase hexadecimal digits. Components here must be
finite and between zero and one; `f32->i32` truncates toward zero. Production
input handling would check those conditions before calling `channel-hex`.

`datatype` covers both structs and closed unions: one constructor makes a
struct, and several constructors make a union. `primary` and `rgb` explicitly
wrap their payloads. This preserves the distinction between the union and its
component types. The class instance for vectors is specifically for F32;
generic instance heads would require an additional language feature. The same
`def` names values, datatypes, typeclasses and instances; their bodies determine
the type or kind of binding being introduced.

## Why a common language?

A Scheme frontend, a small domain-specific language and a handwritten SFIR
library can all produce definitions in the same language. They can share types
and call one another's functions. One compiler then checks and optimizes the
assembled program. Plain data can remain data; a generator embeds it in SFIR
only when the program needs it as a definition.

This also gives builds a useful programming model. Code can construct libraries,
invoke the compiler, and pass the resulting artifacts to other code for
deployment. The same model can describe a server preparing code for a browser
or a host preparing a GPU computation. Each target states which operations and
representations it supports; a common language does not make every program
portable to every target.

Platform services arrive through explicit interfaces. A runtime may offer
continuations, file access or graphics while another omits them. Typed boundaries
help callers agree on the values they exchange. Crossing a process or network
boundary still requires a transport, validation of incoming data and a failure
policy. Those are library and runtime responsibilities.
