# Siegework

**[Play Siegework](../play/siegework/)** in a browser with WebGPU. The game
saves itself in the browser and continues where you left it.

Explore a seeded map, wire an energy network across it, and destroy three
nests before their attacks destroy your hub.

{{#include ../../../apps/siegework/README.md:guide}}

## Reading the code

Siegework's [source](https://github.com/tsnl/snail-scheme/tree/main/apps/siegework)
is a tour of a complete application: seeded terrain, an energy network
derived from the buildings, a siege on a fixed schedule, a world that
changes only through orders and ticks, and a scene and HUD drawn from the
state alone.
