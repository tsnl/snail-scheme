// The same footprints, divergence, slab intersections and checksum as rays.scm.
// The twelve walls and each ray's interval fit in automatic storage.
typedef struct { double west, east, north, south; } Footprint;

static void clip(double *near, double *far, double at, double v, double low, double high) {
    if (__builtin_fabs(v) < 0.0000001) {
        if (at < low || at > high) *near = *far + 1.0;
        return;
    }
    double a = (low - at) / v, b = (high - at) / v;
    double lower = a < b ? a : b, upper = a > b ? a : b;
    if (*near < lower) *near = lower;
    if (*far > upper) *far = upper;
}

__attribute__((export_name("cast-rays")))
double cast_rays(long long count, double seed) {
    Footprint walls[12];
    for (int i = 0; i < 12; ++i) {
        double x = 2.0 + i, z = (i * 7) % 11 - 5.0;
        walls[i] = (Footprint){x - 0.25, x + 0.25, z - 0.625, z + 0.625};
    }
    double sum = 0.0, z = seed;
    for (long long n = count; n > 0; --n) {
        double reach = 40.0, dz = n % 2 == 0 ? 0.0 : 0.125;
        for (int i = 0; i < 12; ++i) {
            double near = 0.0, far = reach;
            clip(&near, &far, 0.0, 1.0, walls[i].west, walls[i].east);
            clip(&near, &far, z, dz, walls[i].north, walls[i].south);
            if (near <= far) reach = near;
        }
        sum += reach;
        z = z > 5.0 ? z - 9.875 : z + 0.28125;
    }
    return sum;
}
