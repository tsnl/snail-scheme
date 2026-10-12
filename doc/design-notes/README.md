# Design notes

These notes preserve implementation sketches and acceptance criteria separately
from [the book](../book/index.md), which explains the model and documents runtime
implementations.

- [Integration checkpoints](integration-checkpoints/index.md) preserve the game,
  chat, and tensor milestones, including checks that require runtime extensions.
- [Native GUI interface sketch](runtimes/native-gui.wat) and
  [browser GUI interface sketch](runtimes/browser-gui.wat) are unimplemented
  interfaces. They are not runtime reference pages.

The sketches and checkpoints retain their original terminology. The book uses
**node** for a running instance and **ABI** for the local runtime interface.
