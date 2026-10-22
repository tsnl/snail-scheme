# Applications

Each application is a directory with a `main.sld` program, its own libraries
under `src/`, an `index.html`, and tests. `scripts/build-app.scm` compiles
`main.sld` and packages it with the shared browser host from `src/app`:

```sh
chibi-scheme -I host/chibi -I src scripts/build-app.scm "$PWD" apps/siegework build/siegework
```

`./lofi serve apps/siegework` builds the same program one library at a
time into `build/serve/siegework`, serves it, and relinks each rebuilt
module into the open page, keeping its state.

| Application | Purpose |
| --- | --- |
| [Siegework](siegework/README.md) | A colony game: explore, mine ore and destroy three nests before their waves arrive. |
