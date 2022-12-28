def fibonacci(n):
    if n <= 1:
        return n
    else:
        return fibonacci(n-1) + fibonacci(n-2)

def fibonacci_loop(n):
    if n <= 1:
        return n
    else:
        p0 = 0
        p1 = 1
        for _ in range(n+1):
            p0, p1 = p1, p0 + p1
        return p1

def fibonacci_numba_loop(n_value):
    import numba
    import time

    @numba.jit()
    def jitted_fibonacci_loop(n: int):
        if n <= 1:
            return n
        else:
            p0 = 0
            p1 = 1
            for _ in range(n+1):
                p0, p1 = p1, p0 + p1
            return p1

    start = time.time()
    jitted_fibonacci_loop(n_value)
    finish = time.time()

    print(f"Excluding compilation and this message, took: {finish - start}")

print(fibonacci_loop(30))
