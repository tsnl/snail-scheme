# Recursive Fibonacci

Recursive Fibonacci · extracted function with a C workload harness

2026-10-10T12:12:56.317699+00:00; CPU 2; 8 rounds; 64 repetitions. Build and startup excluded.

| Implementation | Median seconds | Min–max seconds | Time / Chez |
| --- | ---: | ---: | ---: |
| Snail native translator · tuned | 0.02736 | 0.02491–0.02741 | 0.90× |
| Chez Scheme · safe O2 | 0.03052 | 0.02873–0.03063 | 1.00× |
| Snail native translator · baseline | 0.04749 | 0.04538–0.04758 | 1.56× |
| Guile · bytecode O2 | 0.09657 | 0.09224–0.10204 | 3.16× |
| Guile · after in-process warmup | 0.09585 | 0.09353–0.10651 | 3.14× |
| Chibi Scheme | 0.47100 | 0.46100–0.52000 | 15.43× |
