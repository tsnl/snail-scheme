# HTTP protocol

`(lofi http)` implements a pure, bounded request-head parser and response
serializer, importing only `(lofi base)`. `(lofi http exchange)` reads one complete
request, calls application code and writes its response over the concrete
[socket effects](../runtimes/networking.md). Applications own accepting and
scheduling connections; the library supplies no router or server framework.

This is a deliberate HTTP/1.1 subset. Full HTTP/1.1 also requires features this
module rejects, including chunked decoding and absolute-form targets.
[RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html)

## Request heads

```scheme
(parse-request-head bytes)
;; Result (Option ParsedHead) HttpError
```

`Ok None` means the supplied prefix needs more bytes. `Ok (Some parsed)` contains
a `RequestHead` and the offset of the first body byte. Bytes after that offset
are not inspected, so binary content or a large body cannot invalidate a short
head. The exchange reader reports EOF before a complete head as `TruncatedHead`,
including an empty connection. The parser itself does not establish body receipt.
An incomplete prefix is not a certificate of valid syntax: some errors are
decided once a complete head is available.

The head limit is 16,384 bytes, including the terminating empty line. Input uses
strict CRLF and ASCII, with tab allowed in field values. The method is a token
retained exactly; the target must be origin-form, beginning with `/`. URI
characters and percent escapes are checked, but spelling is preserved: there is
no decoding, path normalization, filesystem lookup or origin authorization.
CONNECT, other target forms and other HTTP versions are unsupported.

Each `Header` contains a lowercase name and a value with surrounding spaces/tabs
removed. Ordinary occurrences retain their order and are not merged.
`header-values` takes the parsed headers and a case-insensitive name, returning
all matching values. It expects the normalized names produced by the parser.

Exactly one Host is required. This implementation accepts a nonempty name made
of ASCII letters, digits, `.`, `-` and `_`, optionally followed by a decimal port
from 0 through 65,535. This is a syntax restriction, not DNS validation. IPv6
literals are unsupported. Exact Host and Origin policy remains with the caller.

A missing Content-Length means body length zero. A single unsigned decimal
length may specify at most 8,388,608 bytes; the parser checks that bound before
arithmetic or body allocation. Duplicate or comma-list lengths and combined
Transfer-Encoding/Content-Length are malformed. Other transfer codings and every
Expect field are unsupported, decided before a caller waits for any body.

`HttpError` distinguishes `Malformed`, `Unsupported`, `HeadTooLarge`,
`BodyTooLarge` and `InvalidResponse`. The reason/feature strings are diagnostics;
the codec does not choose HTTP error responses. Public records remain ordinary
constructible Lofi values. The parser guarantees its own outputs, rather than
making a claim about records created elsewhere.

## Response parts

```scheme
(encode-response method status headers representation)
;; Result ResponseParts HttpError
```

`ResponseParts-head` and `ResponseParts-body` are separate immutable byte vectors.
This avoids copying a representation into one combined response buffer and
leaves a clear boundary for future streaming. No bytes are written by this call.

The serializer accepts final statuses 200–599, with an empty reason phrase.
Successful CONNECT responses are unsupported. It validates ASCII header names
and values and checks the 16,384-byte head bound before building the output
buffer. Caller-supplied Content-Length, Transfer-Encoding, Connection, Trailer
and Upgrade fields are rejected. It generates `Connection: close` and owns
content framing; header strings cannot inject another field or status line.

| Response | Generated Content-Length | Returned body |
| --- | --- | --- |
| 204 or 304 | Omitted | Empty |
| 205 | 0 | Empty |
| HEAD, otherwise | Representation length | Empty |
| Other supported response | Representation length | Original bytes |

Status rules take precedence over HEAD. Response representations are not subject
to the request-body bound. The caller still has to write all head/body bytes and
close appropriately; successful encoding is not delivery.

## One exchange

Import `(lofi http exchange)` and call `serve-one` with an exclusively used
`Connection`, an I32 grace period in milliseconds, and an application function:

```scheme
(: serve-one
   (All (E e)
     (-> Connection I32
         (-> Request (Result Response E) ! e)
         (Result Unit (ExchangeError E)) ! tcp e)))
```

`Request` contains `head : RequestHead` and `body : Bytes`. The callback returns
`Response`, containing `status : I32`, `headers : List Header` and `body : Bytes`,
or an application error of its chosen type `E`. It may suspend for other effects;
the surrounding computation retains those requirements. The callback receives
the request, not the connection.

The reader scans incoming bytes once for the head delimiter and parses the
completed head once. It collects exactly the declared body length, including any
prefix that arrived with the head. Fragment lists are copied once into the final
vectors; one-byte fragmentation does not repeatedly copy the accumulated input.
Unneeded pipelined bytes are discarded. The serializer validates the complete
response before any output, then the writer sends head and body separately,
advancing by each accepted count. HEAD and bodyless statuses use the codec's
rules. No handler call occurs before the complete request body arrives.
Each write offers at most twice the previous accepted count, capped at 65,536;
this bounds slice copying even when an intercepted write makes tiny progress.

`ExchangeError E` distinguishes protocol failure (`HttpError`), transport failure
(`SocketError`), `TruncatedHead`, `TruncatedBody` with expected/received counts,
and `ApplicationFailure E`. Every returned failure closes the connection while
preserving the original error if close also fails. Empty successful reads or
invalid write counts report transport `EIO`, rather than looping without progress.
Protocol/application errors do not generate automatic HTTP error responses.

Success ends with [graceful completion](../runtimes/networking.md#finishing-a-connection)
through `finish-connection`: it ends output, discards input and awaits physical
closure with a bounded grace period. Unread incoming data can otherwise cause a
reset that loses the response; see
[RFC 9112 §9.6](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.6).
This grace is for completion only. There is no request-idle deadline yet.

Exclusive use is a calling convention, not affine ownership. The caller must not
use another alias during the exchange. Cancellation of active native socket I/O
closes that socket. An uncatchable trap or cancellation while the callback waits
on an unrelated effect cannot execute the Lofi cleanup branch; runtime shutdown
cleans the remaining native resource. `serve-one` does not introduce a task scope
or stronger unwinding guarantee.

## Remaining integration

Artifact serving, explicit streaming/SSE, connection scheduling and deadline policy
remain [networking work](https://github.com/tsnl/snail-scheme/issues/457). Existing
project file, status and origin policies remain in the native project service.
Persistent connections, pipelining and streaming uploads are not implemented.
