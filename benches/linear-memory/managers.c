// Same wall layout, visit order, slab arithmetic, grid and queue as managers.scm.
// Both entry points receive their input at runtime. Build with -DCHECK_BOUNDS
// for a C control with trapping vector subscripts.
typedef long long I64;
typedef unsigned long long U64;
#ifdef __wasm__
#define EXPORT(name) __attribute__((export_name(name)))
#else
#define EXPORT(name)
#endif

static I64 index_at(I64 i, I64 length) {
#ifdef CHECK_BOUNDS
    if ((U64)i >= (U64)length) __builtin_trap();
#else
    (void)length;
#endif
    return i;
}

typedef struct { double west, east, north, south; } Wall;
typedef struct { I64 slot; } WallId;
enum { max_walls = 4096 };
typedef struct {
    I64 count;
    Wall bounds[max_walls];
    WallId ids[max_walls];
} Walls;

EXPORT("prepare-walls")
Walls *prepare_walls(I64 count, I64 phase) {
    static Walls walls;
    if ((U64)count > max_walls) __builtin_trap();
    walls.count = count;
    for (I64 i = 0; i < count; ++i) {
        double x = 2.0 + (i % 31), z = (i * 7 + phase) % 11 - 5.0;
        walls.bounds[i] = (Wall){x - 0.25, x + 0.25, z - 0.625, z + 0.625};
        walls.ids[i] = (WallId){i};
    }
    I64 state = phase + 1;
    for (I64 i = count - 1; i > 0; --i) {
        state = (state * 48271) % 2147483647;
        I64 j = state % (i + 1);
        WallId saved = walls.ids[i];
        walls.ids[i] = walls.ids[j];
        walls.ids[j] = saved;
    }
    return &walls;
}

static double intersect(const Wall *wall, double z, double dz, double reach) {
    double near = wall->west > 0 ? wall->west : 0;
    double far = wall->east < reach ? wall->east : reach;
    if (dz == 0)
        return z >= wall->north && z <= wall->south && near <= far ? near : reach;
    double a = (wall->north - z) / dz, b = (wall->south - z) / dz;
    double entry = near > a ? near : a, exit = far < b ? far : b;
    return entry <= exit ? entry : reach;
}

static double trace(const Walls *walls, double z, double dz, int keyed) {
    double reach = 40.0;
    for (I64 i = 0; i < walls->count; ++i) {
        I64 slot = keyed ? walls->ids[i].slot : i;
        reach = intersect(&walls->bounds[index_at(slot, walls->count)], z, dz, reach);
    }
    return reach;
}

EXPORT("cast")
double cast(const Walls *walls, I64 count, double seed, int keyed) {
    double z = seed, sum = 0.0;
    for (I64 n = count; n > 0; --n) {
        double dz = n % 2 == 0 ? 0.0 : 0.125;
        sum += trace(walls, z, dz, keyed);
        z = z > 5.0 ? z - 9.875 : z + 0.28125;
    }
    return sum;
}

enum { side = 80, cells = side * side };
typedef struct { int open[cells]; I64 distance[cells], queue[cells]; } Grid;

EXPORT("prepare-grid")
Grid *prepare_grid(void) {
    static Grid grid;
    return &grid;
}

EXPORT("set-open")
void set_open(Grid *grid, I64 slot, int open) {
    grid->open[index_at(slot, cells)] = open;
}

EXPORT("grid-distance")
I64 grid_distance(const Grid *grid, I64 slot) {
    return grid->distance[index_at(slot, cells)];
}

static I64 enqueue(Grid *grid, I64 slot, I64 steps, I64 end) {
    slot = index_at(slot, cells);
    if (grid->open[slot] && grid->distance[slot] == -1) {
        grid->distance[slot] = steps;
        grid->queue[index_at(end, cells)] = slot;
        ++end;
    }
    return end;
}

EXPORT("packed-field")
void packed_field(Grid *grid, I64 goal) {
    for (I64 i = 0; i < cells; ++i) grid->distance[i] = -1;
    grid->distance[index_at(goal, cells)] = 0;
    grid->queue[0] = goal;
    I64 end = 1;
    for (I64 next = 0; next < end; ++next) {
        I64 slot = grid->queue[index_at(next, cells)], steps = grid_distance(grid, slot) + 1;
        I64 x = slot % side;
        if (x + 1 < side) end = enqueue(grid, slot + 1, steps, end);
        if (x > 0) end = enqueue(grid, slot - 1, steps, end);
        if (slot + side < cells) end = enqueue(grid, slot + side, steps, end);
        if (slot >= side) end = enqueue(grid, slot - side, steps, end);
    }
}
