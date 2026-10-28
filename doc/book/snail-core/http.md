# HTTP protocol

`(snail shell http)` implements a pure, bounded request-head parser, a
request-target decoder and response serializers, importing only
`(snail core base)` and `(snail shell utf8)`. `(snail shell http exchange)` reads one complete
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

## Request targets

```scheme
(parse-target (RequestHead-target head))
;; Result Target HttpError
```

`parse-target` decodes an origin-form target as `new URL` and
`URLSearchParams` read it. `Target-path` is the segments after the first `/`,
split before decoding, so `/` is `("")` and `/a%2Fb/` is `("a/b" "")`. Dot
segments are resolved after decoding, `%2e%2e` included, as the URL standard
does: `/a/b/..` is `("a" "")`. `Target-query` is the query's name and value
pairs in order: `&` separates pairs, empty pieces are skipped, the first `=`
ends a name, and `+` is a space before decoding, so `%2B` stays a plus.
`assoc-ref` finds a name's first value, as `URLSearchParams.get` does.

Decoding is strict where the URL standard is lenient. A `%` without two hex
digits, a character outside the target's URI characters, and escaped bytes
that are not UTF-8 are all `Malformed`; Node keeps a bad escape as text and
replaces bad UTF-8 with U+FFFD. Targets that `encodeURIComponent` builds always
decode. A target without a leading `/` is `Unsupported`.

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
constructible Snail-Core values. The parser guarantees its own outputs, rather than
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

## Stream heads

```scheme
(encode-stream-head status headers)
;; Result Bytes HttpError
```

A stream's head has no Content-Length: its body is every byte written after
it, ending when the server closes the connection
([RFC 9112 §6.3](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3),
rule 8). This is how an event stream is framed in this subset, which has no
chunked coding. The head is checked as `encode-response` checks one, with the
same `Connection: close` and framing rules. Statuses that forbid a body, 204,
205 and 304, have no stream; a HEAD request is answered with
`encode-response` instead.

## One exchange

Import `(snail shell http exchange)` and call `serve-one` with an exclusively used
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
on an unrelated effect cannot execute the Snail-Core cleanup branch; runtime shutdown
cleans the remaining native resource. `serve-one` does not introduce a task scope
or stronger unwinding guarantee.

`read-request` and `respond` are the exchange's two halves, exported for a
server that decides between reading a request and answering it. `serve-one`
is them with one handler between, closing the connection when either fails;
called directly, a failure from either leaves the connection open, and the
caller closes it.

## Remaining integration

Artifact serving, writing event streams after their heads, connection scheduling
and deadline policy remain
[networking work](https://github.com/tsnl/snail-scheme/issues/457). Existing
project file, status and origin policies remain in the native project service.
Persistent connections, pipelining and streaming uploads are not implemented.
