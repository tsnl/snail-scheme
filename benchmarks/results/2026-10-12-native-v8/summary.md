# R7RS suite

Upstream `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1` · 3 rounds · original inputs

Build/startup excluded. Each successful result passed the upstream result predicate.

| Benchmark | snail-native | snail-wasm | chez |
| --- | ---: | ---: | ---: |
| [browse](plots/browse.svg) | 1.44682s | 0.757711s | 0.524319s |
| [deriv](plots/deriv.svg) | 29.3135s | 6.08035s | 0.418243s |
| [destruc](plots/destruc.svg) | 14.8388s | 5.34246s | 0.934982s |
| [diviter](plots/diviter.svg) | 6.6621s | 2.63349s | 0.769968s |
| [divrec](plots/divrec.svg) | 7.4667s | 2.51067s | 0.935794s |
| [puzzle](plots/puzzle.svg) | runtime-error | runtime-error | 0.959086s |
| [triangl](plots/triangl.svg) | 14.8171s | 5.30006s | 0.852085s |
| [tak](plots/tak.svg) | 2.15244s | 3.24495s | 0.640388s |
| [takl](plots/takl.svg) | 34.3631s | 13.7559s | 2.51474s |
| [ntakl](plots/ntakl.svg) | 3.67475s | 4.05604s | 2.51937s |
| [cpstak](plots/cpstak.svg) | 29.2094s | 7.7669s | 1.7815s |
| [ctak](plots/ctak.svg) | runtime-error | runtime-error | 0.250629s |
| [fib](plots/fib.svg) | 2.35785s | 3.67952s | 1.38752s |
| [fibc](plots/fibc.svg) | runtime-error | runtime-error | 0.181884s |
| [fibfp](plots/fibfp.svg) | 15.3009s | 3.69119s | 0.860671s |
| [sum](plots/sum.svg) | 4.19541s | 5.2004s | 1.03697s |
| [sumfp](plots/sumfp.svg) | 27.1523s | 7.51878s | 1.09764s |
| [fft](plots/fft.svg) | 8.15364s | 4.25751s | 0.782726s |
| [mbrot](plots/mbrot.svg) | 22.3442s | 7.77094s | 2.25613s |
| [mbrotZ](plots/mbrotZ.svg) | 39.2272s | 13.1331s | 1.44921s |
| [nucleic](plots/nucleic.svg) | 13.2106s | 4.93507s | 0.735103s |
| [pi](plots/pi.svg) | runtime-error | runtime-error | 0.213335s |
| [pnpoly](plots/pnpoly.svg) | 32.5946s | 8.99335s | 1.50732s |
| [ray](plots/ray.svg) | 17.5158s | 4.88171s | 0.848329s |
| [simplex](plots/simplex.svg) | 26.0098s | 7.31572s | 0.718141s |
| [ack](plots/ack.svg) | 4.395s | runtime-error | 0.815562s |
| [array1](plots/array1.svg) | 23.2108s | 10.6665s | 6.86413s |
| [string](plots/string.svg) | 2.51796s | 4.9225s | 0.950325s |
| [sum1](plots/sum1.svg) | 0.567553s | 0.569233s | 0.40042s |
| [cat](plots/cat.svg) | 24.6317s | 22.6705s | 0.696605s |
| [tail](plots/tail.svg) | 3.78236s | 4.88367s | 0.943435s |
| [wc](plots/wc.svg) | 27.1233s | 12.4021s | 0.644518s |
| [read1](plots/read1.svg) | 1.2658s | 1.49933s | 0.319656s |
| [compiler](plots/compiler.svg) | build-error | build-error | 0.8239s |
| [conform](plots/conform.svg) | 25.956s | 10.7621s | 0.888628s |
| [dynamic](plots/dynamic.svg) | 14.0622s | 8.40716s | 0.857024s |
| [earley](plots/earley.svg) | 71.4254s | 9.06644s | 1.78594s |
| [graphs](plots/graphs.svg) | 114.635s | 12.3329s | 0.766161s |
| [lattice](plots/lattice.svg) | 65.5702s | 24.8956s | 1.1554s |
| [matrix](plots/matrix.svg) | 17.0991s | 5.30571s | 0.476652s |
| [maze](plots/maze.svg) | runtime-error | runtime-error | 0.33119s |
| [mazefun](plots/mazefun.svg) | 12.1383s | 5.49072s | 1.02021s |
| [nqueens](plots/nqueens.svg) | 20.2798s | 12.3787s | 2.63148s |
| [paraffins](plots/paraffins.svg) | 2.36123s | 6.36679s | 2.62681s |
| [parsing](plots/parsing.svg) | 22.7941s | 14.7405s | 1.19442s |
| [peval](plots/peval.svg) | 29.6879s | 11.0837s | 0.846119s |
| [primes](plots/primes.svg) | 4.06501s | 1.21958s | 0.414034s |
| [quicksort](plots/quicksort.svg) | runtime-error | runtime-error | 1.78077s |
| [scheme](plots/scheme.svg) | 29.1604s | 11.2756s | 0.988768s |
| [slatex](plots/slatex.svg) | 6.41599s | 4.18551s | 1.05507s |
| [chudnovsky](plots/chudnovsky.svg) | runtime-error | runtime-error | 0.0868381s |
| [nboyer](plots/nboyer.svg) | 6.50979s | 5.3799s | 0.880527s |
| [sboyer](plots/sboyer.svg) | 4.65002s | 2.66949s | 0.372375s |
| [gcbench](plots/gcbench.svg) | 14.9603s | 4.74334s | 0.390911s |
| [mperm](plots/mperm.svg) | 16.7471s | 20.4418s | 4.57438s |
| [equal](plots/equal.svg) | runtime-timeout | runtime-timeout | 0.254073s |
| [bv2string](plots/bv2string.svg) | 5.41343s | 3.51614s | 0.471077s |
