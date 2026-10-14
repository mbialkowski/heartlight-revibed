/* Heartlight PC rules in C (a port of tools/hl_sim.py, checked against the golden traces by
 * tools/solve_levels.py) and a beam-search solver for the 70 levels.
 *
 *   cc -O2 -shared -fPIC -o hlsolve.so hlsolve.c
 *
 * Used from Python with ctypes (tools/solve_levels.py): sim_new / sim_tick / sim_hash to verify
 * the port, solve() to look for a solution (a string of per-tick inputs ". L R U D").
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define W 22
#define H 14
#define N (W * H)

enum { EMPTY, EXPLOSION, BRICK, METAL, ROCK, HEART, BOMB, GRASS, DWARF, DOOR, BALLOON, PLASMA,
       TUNNEL_L, TUNNEL_R };
enum { PLAYING = 1, NEXT_LEVEL = 6 };

typedef struct {
    uint8_t type[N], state[N], frame[N], pending[N];
    int hearts_left, hearts_total, game_state, death_timer, exit_timer, idle, activity, dir;
    int tick_count, level_index;
    uint32_t rand;
} Sim;

static int rnd(Sim *s) {
    s->rand = s->rand * 0x015A4E35u + 1u;
    return (s->rand >> 16) & 0x7FFF;
}

void sim_setup(Sim *s, const char *rows) {
    /* rows: 12 lines of 20 characters, no separators */
    memset(s->type, METAL, N);
    memset(s->state, 0, N);
    memset(s->frame, 0, N);
    memset(s->pending, 1, N);
    s->hearts_left = 0;
    for (int x = 0; x < 20; x++)
        for (int y = 0; y < 12; y++) {
            char c = rows[y * 20 + x];
            int si = (y + 1) * W + (x + 1), t = METAL, st = 2, f = 0;
            switch (c) {
            case ' ': t = EMPTY; st = 0; break;
            case '#': t = BRICK; st = 0; f = s->level_index % 4; break;
            case '%': t = METAL; st = 0; break;
            case '@': t = ROCK; break;
            case '$': t = HEART; f = rnd(s) * 6 / 0x8000; s->hearts_left++; break;
            case '*': t = DWARF; st = 1; f = x < 10 ? 2 : 0; break;
            case '!': t = DOOR; st = 5; break;
            case '&': t = BOMB; break;
            case '.': t = GRASS; st = 0; break;
            case '0': t = BALLOON; f = rnd(s) * 4 / 0x8000; break;
            case '=': t = PLASMA; break;
            case '<': t = TUNNEL_L; break;
            case '>': t = TUNNEL_R; break;
            }
            s->type[si] = t; s->state[si] = st; s->frame[si] = f;
        }
    s->hearts_total = s->hearts_left;
    s->game_state = PLAYING;
    s->death_timer = s->exit_timer = 0;
    s->idle = s->activity = 1;
    s->dir = 0;
}

static void move_(Sim *s, int src, int dst, int st) {
    s->type[dst] = s->type[src];
    s->state[dst] = st < 0 ? s->state[src] : st;
    s->frame[dst] = s->frame[src];
    s->pending[dst] = 0;
    s->type[src] = s->state[src] = s->frame[src] = 0;
}

static void clear_(Sim *s, int i) { s->type[i] = s->state[i] = s->frame[i] = 0; }

static void hero_to(Sim *s, int si, int di, int f) {
    s->type[di] = DWARF; s->state[di] = 1; s->frame[di] = f; s->pending[di] = 0;
    clear_(s, si);
}

static void hero_think(Sim *s, int si) {
    s->activity++;
    s->idle = 0x20;
    if (s->death_timer) {
        if (s->death_timer > 1) s->frame[si] = 4 | (s->death_timer & 1);
        else { s->type[si] = EXPLOSION; s->state[si] = 1; s->frame[si] = 0; }
        return;
    }
    if (s->exit_timer) {
        if (s->exit_timer > 1) s->frame[si] = 6 | (s->exit_timer & 1);
        else s->game_state = NEXT_LEVEL;
        return;
    }
    int f = s->frame[si], d = s->dir;
    if (d == -1) f = (f ^ 1) & 1;
    else if (d == 1) f = (f ^ 1) | 2;
    else if (d == -W || d == W) f = (f & 2) | (f ^ 1);
    if (d == 0) { s->frame[si] = f & 2; return; }
    int di = si + d, t = s->type[di];
    if (t == EMPTY || t == GRASS) hero_to(s, si, di, f);
    else if (t == ROCK || t == BOMB || t == BALLOON) {
        if (s->type[si + 2 * d] == EMPTY && s->state[di] == 2 && s->state[di - W] != 3 && d != -W && d != W) {
            if (s->tick_count & 1) {
                int j = si + 2 * d;
                s->type[j] = s->type[di]; s->state[j] = s->state[di]; s->frame[j] = s->frame[di];
                s->pending[j] = 0;
                hero_to(s, si, di, f);
            } else s->frame[si] = f;
        } else s->frame[si] = f & 2;
    } else if (t == HEART) {
        if (s->state[di] == 2) { hero_to(s, si, di, f); s->hearts_left--; }
    } else if (t == DOOR) {
        if (s->state[di] == 6) { hero_to(s, si, di, f); s->exit_timer = 0x10; }
        else s->frame[si] = f & 2;
    } else if (t == TUNNEL_L || t == TUNNEL_R) {
        if ((t == TUNNEL_L && d == -1) || (t == TUNNEL_R && d == 1)) {
            int j = di;
            while (s->type[j] == t) j += d;
            if (s->type[j] == EMPTY || s->type[j] == GRASS) {
                s->state[di] = 1; s->pending[di] = 0; clear_(s, si);
                return;
            }
        }
        s->frame[si] = f & 2;
    } else s->frame[si] = f & 2;
}

static void tunnel_think(Sim *s, int si) {
    int st = s->state[si], d = s->type[si] == TUNNEL_L ? -1 : 1;
    if (st == 1) {
        s->activity++; s->idle = 0x20;
        s->frame[si] = ((s->frame[si] + 1) & 3) | 4;
        s->state[si] = 2;
        int n = si + d, t = s->type[n];
        if (t == TUNNEL_L || t == TUNNEL_R) {
            if (t == s->type[si]) { s->state[n] = 1; s->pending[n] = 0; }
        } else if (t == EMPTY || t == GRASS) s->state[si] = 3;
    } else if (st == 2) s->frame[si] = (s->frame[si] + 1) & 3;
    else if (st == 3) {
        s->activity++; s->idle = 0x20;
        s->frame[si] = (s->frame[si] + 1) & 3;
        s->state[si] = 2;
        int n = si + d;
        if (s->type[n] == GRASS || s->type[n] == EMPTY) {
            s->type[n] = DWARF; s->state[n] = 1; s->frame[n] = s->type[si] == TUNNEL_L ? 0 : 2;
            s->pending[n] = 0;
        }
    }
}

static int gravity(Sim *s, int di) {
    int landed = 0;
    if (s->state[di] == 2) {
        int b = s->type[di + W];
        if (b == EMPTY) { s->state[di] = 3; s->activity++; }
        else if (b == EXPLOSION || b == BRICK || b == ROCK || b == HEART || b == PLASMA ||
                 (b == BOMB && s->frame[di + W] == 0)) {
            if (s->type[di - 1] == EMPTY && s->type[di + W - 1] == EMPTY && s->state[di - W - 1] != 3) {
                move_(s, di, di - 1, 3); s->activity++;
            } else if (s->type[di + 1] == EMPTY && s->type[di + W + 1] == EMPTY && s->state[di - W + 1] != 3) {
                move_(s, di, di + 1, 3); s->activity++;
            }
        } else if (b == BALLOON) {
            int a = s->type[di - W];
            if (s->type[di + 2 * W] == EMPTY && (a == ROCK || a == HEART || a == BOMB)) {
                move_(s, di + W, di + 2 * W, -1);
                s->state[di] = 3;
            }
        }
    }
    if (s->state[di] == 3) {
        s->activity++;
        int b = s->type[di + W];
        if (b == EMPTY) move_(s, di, di + W, -1);
        else if (b == BOMB) { s->state[di + W] = 8; s->state[di] = 2; landed = 1; }
        else if (b == DWARF) {
            if (s->frame[di + W] < 6) {
                s->type[di + W] = EXPLOSION; s->state[di + W] = 1; s->frame[di + W] = 0;
                s->pending[di + W] = 0;
            }
            s->state[di] = 2; landed = 1;
        } else { s->state[di] = 2; landed = 1; }
    }
    return landed;
}

static void bomb_think(Sim *s, int di) {
    if (gravity(s, di)) {
        if (s->type[di + W] != GRASS) s->state[di] = 8;
    }
    if (s->state[di] != 8) return;
    if (s->frame[di] == 0) {
        s->frame[di] = 1;
        int b = di + W;
        if (s->type[b] == DWARF && s->frame[b] >= 6) return;
        if (s->type[b] == BOMB) return;
        s->pending[b] = 0;
        return;
    }
    s->type[di] = EXPLOSION; s->state[di] = 1; s->frame[di] = 1;
    static const int dd[4] = { -1, 1, -W, W };
    for (int k = 0; k < 4; k++) {
        int n = di + dd[k], t = s->type[n];
        if (t == METAL || t == TUNNEL_L || t == TUNNEL_R) continue;
        if (t == BOMB) { s->state[n] = 8; s->pending[n] = 0; continue; }
        if (t == DWARF && s->frame[n] >= 6) continue;
        s->type[n] = EXPLOSION; s->state[n] = 1; s->frame[n] = 0;
    }
}

static void balloon_think(Sim *s, int di) {
    s->frame[di] = (s->frame[di] + 1) & 3;
    if (s->state[di] == 2) {
        int a = s->type[di - W];
        if (a == EMPTY) { s->state[di] = 7; s->activity++; }
        else if (a == ROCK || a == HEART || a == BOMB || a == DWARF) {
            if (s->type[di - 2 * W] == EMPTY) {
                int j = di - 2 * W, k = di - W;
                s->type[j] = s->type[k]; s->state[j] = s->state[k]; s->frame[j] = s->frame[k];
                clear_(s, k);
                s->state[di] = 7;
            }
        }
    }
    if (s->state[di] == 7) {
        s->activity++;
        if (s->type[di - W] == EMPTY) move_(s, di, di - W, -1);
        else s->state[di] = 2;
    }
}

static void door_think(Sim *s, int si) {
    if (s->frame[si] < 3) {
        if (s->hearts_left == 0) s->frame[si]++;
    } else s->state[si] = 6;
}

void sim_tick(Sim *s, int direction, int escape) {
    s->activity = 0;
    s->dir = direction;
    if (escape && s->death_timer == 0 && s->exit_timer == 0) s->death_timer = 8;
    memset(s->pending, 1, N);
    for (int y = 1; y < 13; y++)
        for (int x = 1; x < 21; x++) {
            int si = y * W + x;
            if (s->state[si] == 0 || s->pending[si] == 0) continue;
            switch (s->type[si]) {
            case EXPLOSION:
                s->activity++;
                if (s->frame[si] < 6) s->frame[si]++; else clear_(s, si);
                break;
            case ROCK: gravity(s, si); break;
            case HEART:
                s->frame[si] = (s->frame[si] + 1) % 6;
                if (gravity(s, si) && s->type[si + W] != GRASS) rnd(s);    /* heart sound */
                break;
            case BOMB: bomb_think(s, si); break;
            case DWARF: hero_think(s, si); break;
            case DOOR: door_think(s, si); break;
            case BALLOON: balloon_think(s, si); break;
            case PLASMA: s->frame[si] = (s->frame[si] + 1) & 7; break;
            case TUNNEL_L: case TUNNEL_R: tunnel_think(s, si); break;
            }
        }
    s->tick_count = (s->tick_count + 1) & 0xFFFF;
    s->idle--;
    if (s->death_timer) s->death_timer--;
    if (s->exit_timer) s->exit_timer--;
}

static int running(const Sim *s) { return s->game_state == PLAYING && s->activity != 0 && s->idle != 0; }

/* ---- the Python interface used to verify the port ---- */
static Sim g;
static char g_rows[240];

void sim_new(const char *rows, int level_index, unsigned seed, int tick_count) {
    memcpy(g_rows, rows, 240);
    g.level_index = level_index; g.rand = seed; g.tick_count = tick_count;
    sim_setup(&g, rows);
}

/* one tick like make_golden_traces.run(); returns 0 running, 1 restarted, 2 level ended */
int sim_step(int direction, int escape) {
    sim_tick(&g, direction, escape);
    if (!running(&g)) {
        if (g.game_state != PLAYING) return 2;
        return 1;
    }
    return 0;
}

void sim_restart(void) { sim_setup(&g, g_rows); }

uint32_t sim_hash(void) {
    uint32_t h = 0x811C9DC5u;
    const uint8_t *arrs[3] = { g.type, g.state, g.frame };
    for (int a = 0; a < 3; a++)
        for (int i = 0; i < N; i++) { h ^= arrs[a][i]; h *= 0x01000193u; }
    int v[7] = { g.hearts_left, g.death_timer, g.exit_timer, g.game_state, g.idle, g.activity, g.tick_count };
    for (int k = 0; k < 7; k++) { h ^= (uint32_t)(v[k] & 0xFF); h *= 0x01000193u; }
    return h;
}

/* ---- the solver: beam search over ticks ---- */
typedef struct { Sim s; int parent; char move; int score; uint32_t bucket; } Node;
static int brick_cost = 20, per_bucket = 4, prune_off = 0;
int diag_best_hearts, diag_depth, diag_beam_size, diag_seen;
char diag_path[8192];

static uint64_t key_of(const Sim *s) {
    /* everything the rules read: types, states, the frames that matter, timers, push parity */
    uint64_t h = 1469598103934665603ull;
    for (int i = W; i < N - W; i++) {
        int t = s->type[i];
        uint64_t v = (uint64_t)t | ((uint64_t)s->state[i] << 4);
        if (t == DWARF || t == BOMB || t == EXPLOSION || t == DOOR) v |= (uint64_t)s->frame[i] << 8;
        h ^= v; h *= 1099511628211ull;
    }
    uint64_t c[5] = { (uint64_t)s->hearts_left, (uint64_t)s->death_timer, (uint64_t)s->exit_timer,
                      (uint64_t)(s->tick_count & 1), (uint64_t)s->idle };
    for (int k = 0; k < 5; k++) { h ^= c[k]; h *= 1099511628211ull; }
    return h;
}

/* open-addressing set of 64-bit keys */
static uint64_t *seen; static size_t seen_cap, seen_n;
static int seen_add(uint64_t k) {
    if (k == 0) k = 1;
    if (seen_n * 2 >= seen_cap) return 0;
    size_t i = k & (seen_cap - 1);
    while (seen[i]) { if (seen[i] == k) return 0; i = (i + 1) & (seen_cap - 1); }
    seen[i] = k; seen_n++;
    return 1;
}

static int dist_to(const Sim *s, int want_door, int *reach_hearts) {
    /* BFS from the dwarf over cells he can enter (rocks/bombs/balloons cost more: pushing) */
    static int dist[N], q[N * 4];
    int hero = -1;
    for (int i = 0; i < N; i++) { dist[i] = 1 << 20; if (s->type[i] == DWARF) hero = i; }
    if (hero < 0) {
        for (int i = 0; i < N; i++)
            if ((s->type[i] == TUNNEL_L || s->type[i] == TUNNEL_R) && s->state[i] != 2) hero = i;
        if (hero < 0) return -1;
    }
    int qh = 0, qt = 0, best = 1 << 20, bombs = 0;
    for (int i = 0; i < N; i++) if (s->type[i] == BOMB) bombs++;
    *reach_hearts = 0;
    dist[hero] = 0; q[qt++] = hero;
    static const int dd[4] = { -1, 1, -W, W };
    while (qh < qt) {
        int c = q[qh++];
        for (int k = 0; k < 4; k++) {
            int n = c + dd[k], t = s->type[n], cost = 1;
            if (t == METAL) continue;
            if (t == ROCK || t == BOMB || t == BALLOON) cost = 6;
            if (t == BRICK || t == PLASMA) {               /* only a bomb can open them */
                if (!bombs) continue;
                cost = brick_cost;
            }
            if (t == EXPLOSION) cost = 2;
            if (t == TUNNEL_L || t == TUNNEL_R) cost = 2;
            if (t == DOOR && !want_door) continue;
            if (dist[c] + cost < dist[n]) {
                dist[n] = dist[c] + cost;
                if (qt < N * 4) q[qt++] = n;
            }
        }
    }
    for (int i = 0; i < N; i++) {
        if (want_door ? s->type[i] == DOOR : s->type[i] == HEART) {
            if (dist[i] < best) best = dist[i];
            if (!want_door && dist[i] < (1 << 20)) (*reach_hearts)++;
        }
    }
    return best;
}

static int score_of(const Sim *s, int noise) {
    int rh = 0;
    int d = dist_to(s, s->hearts_left == 0, &rh);
    if (d < 0) return 1 << 28;
    int unreach = s->hearts_left - rh;
    if (unreach > 0 || d >= (1 << 20)) return -1;       /* a heart or the door is out of reach */
    {
        int rh2;                                          /* the door must stay reachable too */
        if (s->hearts_left > 0 && dist_to(s, 1, &rh2) >= (1 << 20)) return -1;
    }
    return s->hearts_left * 300 + unreach * 200 + d * 4 + noise;
}

static int alive(const Sim *s) {
    if (s->death_timer) return 0;
    for (int i = 0; i < N; i++) {
        if (s->type[i] == DWARF) return 1;
        if ((s->type[i] == TUNNEL_L || s->type[i] == TUNNEL_R) && s->state[i] != 2) return 1;
    }
    return 0;
}

static int cmp_node(const void *a, const void *b) {
    return ((const Node *)a)->score - ((const Node *)b)->score;
}

/* states that look alike for the search: where the dwarf is, hearts, bricks and bombs left */
static uint32_t bucket_of(const Sim *s) {
    /* the layout without timing details: every cell's object and its state */
    uint32_t h = 2166136261u;
    for (int i = W; i < N - W; i++) { h ^= (uint32_t)s->type[i] | ((uint32_t)s->state[i] << 4); h *= 16777619u; }
    return h;
}

/* bucket counters for one depth */
static uint32_t *bk_key; static uint8_t *bk_cnt; static size_t bk_cap;
static int bucket_take(uint32_t b) {
    if (b == 0) b = 1;
    size_t i = b & (bk_cap - 1);
    while (bk_key[i] && bk_key[i] != b) i = (i + 1) & (bk_cap - 1);
    bk_key[i] = b;
    if (bk_cnt[i] >= per_bucket) return 0;
    bk_cnt[i]++;
    return 1;
}

/* returns the length of the solution written to out (". L R U D" per tick), or -1 */
int solve(const char *rows, int level_index, int beam, int max_ticks, int tick_count, unsigned seed,
          char *out) {
    brick_cost = 12 + (int)(seed % 3) * 8;
    diag_best_hearts = 999;
    per_bucket = seed % 2 ? 4 : 2;
    prune_off = (seed & 16) != 0;
    if (seed & 32) per_bucket = 255;
    static const int dirs[5] = { 0, -1, 1, -W, W };
    static const char names[5] = { '.', 'L', 'R', 'U', 'D' };
    bk_cap = 1; while (bk_cap < (size_t)beam * 20) bk_cap <<= 1;
    bk_key = calloc(bk_cap, 4); bk_cnt = calloc(bk_cap, 1);
    seen_cap = (size_t)1 << 26;
    seen = calloc(seen_cap, 8); seen_n = 0;
    /* tree of moves: parent index and move per node, kept for every depth */
    size_t tree_cap = (size_t)beam * 5 * (size_t)(max_ticks + 1) + 1;
    if (tree_cap > ((size_t)1 << 28)) tree_cap = (size_t)1 << 28;
    int *tparent = malloc(tree_cap * sizeof(int));
    char *tmove = malloc(tree_cap);
    size_t tn = 0;
    Node *cur = malloc(sizeof(Node) * beam), *nxt = malloc(sizeof(Node) * (size_t)beam * 5);
    int ncur = 1, result = -1;
    unsigned noise_state = seed * 2654435761u + 12345;
    cur[0].s.level_index = level_index; cur[0].s.rand = 1; cur[0].s.tick_count = tick_count;
    sim_setup(&cur[0].s, rows);
    tparent[0] = -1; tmove[0] = 0; cur[0].parent = 0; tn = 1;
    seen_add(key_of(&cur[0].s));
    for (int depth = 0; depth < max_ticks && ncur > 0 && result < 0; depth++) {
        int nn = 0;
        for (int i = 0; i < ncur && result < 0; i++) {
            for (int m = 0; m < 5; m++) {
                Node *n = &nxt[nn];
                n->s = cur[i].s;
                sim_tick(&n->s, dirs[m], 0);
                if (n->s.game_state == NEXT_LEVEL || n->s.exit_timer) {
                    /* the dwarf is in the door: keep still until the level ends */
                    if (tn >= tree_cap) break;
                    tparent[tn] = cur[i].parent; tmove[tn] = names[m];
                    int node = (int)tn++;
                    int len = 0;
                    char tmp[8192];
                    for (int k = node; k > 0 && len < 8000; k = tparent[k]) tmp[len++] = tmove[k];
                    for (int k = 0; k < len; k++) out[k] = tmp[len - 1 - k];
                    Sim t = n->s;
                    while (t.game_state != NEXT_LEVEL && len < 8000) { sim_tick(&t, 0, 0); out[len++] = '.'; }
                    out[len] = 0;
                    result = len;
                    break;
                }
                if (!running(&n->s) || !alive(&n->s)) continue;
                if (!seen_add(key_of(&n->s))) continue;
                if (tn >= tree_cap) continue;
                tparent[tn] = cur[i].parent; tmove[tn] = names[m];
                n->parent = (int)tn++;
                noise_state = noise_state * 1103515245u + 12345u;
                n->score = score_of(&n->s, (noise_state >> 16) % 7);
                if (n->score < 0) { if (!(prune_off)) continue; n->score = 1 << 27; }
                n->bucket = bucket_of(&n->s);
                nn++;
            }
        }
        if (result >= 0) break;
        diag_depth = depth; diag_beam_size = nn; diag_seen = (int)seen_n;
        for (int i = 0; i < nn; i++) if (nxt[i].s.hearts_left < diag_best_hearts) diag_best_hearts = nxt[i].s.hearts_left;
        qsort(nxt, nn, sizeof(Node), cmp_node);
        memset(bk_key, 0, bk_cap * 4); memset(bk_cnt, 0, bk_cap);
        ncur = 0;
        for (int i = 0; i < nn && ncur < beam; i++)
            if (bucket_take(nxt[i].bucket)) cur[ncur++] = nxt[i];
        if (ncur > 0) {
            int len = 0; char tmp[8192];
            for (int k = cur[0].parent; k > 0 && len < 8000; k = tparent[k]) tmp[len++] = tmove[k];
            for (int k = 0; k < len; k++) diag_path[k] = tmp[len - 1 - k];
            diag_path[len] = 0;
        }
        if (seen_n * 2 >= seen_cap) break;
    }
    free(bk_key); free(bk_cnt);
    free(seen); free(tparent); free(tmove); free(cur); free(nxt);
    return result;
}

/* debugging: the state as bytes (type, state, frame, then the counters) */
void sim_dump(uint8_t *out) {
    memcpy(out, g.type, N); memcpy(out + N, g.state, N); memcpy(out + 2 * N, g.frame, N);
    int v[7] = { g.hearts_left, g.death_timer, g.exit_timer, g.game_state, g.idle, g.activity, g.tick_count };
    for (int k = 0; k < 7; k++) out[3 * N + k] = (uint8_t)v[k];
}
