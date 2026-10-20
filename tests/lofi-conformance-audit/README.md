These fixtures check lexical class evidence, concrete declared requirements,
recursive captures and the value restriction. The runner uses the existing Lofi
integration harness and checks every listed source on raw and optimized Wasm:

```sh
chibi-scheme -I bootstrap -I tests tests/lofi-conformance-audit/check.scm --output /tmp/lofi-conformance
```
