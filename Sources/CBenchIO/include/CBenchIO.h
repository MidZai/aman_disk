#ifndef CBENCHIO_H
#define CBENCHIO_H

#include <stdint.h>

typedef enum { CBENCH_SEQ = 0, CBENCH_RND = 1 } cbench_pattern;
typedef enum { CBENCH_READ = 0, CBENCH_WRITE = 1 } cbench_direction;

typedef struct {
    cbench_pattern   pattern;
    cbench_direction direction;
    uint32_t block_size;      // 1048576 or 4096
    uint32_t queue_depth;     // number of threads, 1 to 64
    uint64_t file_size;       // multiple of block_size
    double   max_seconds;     // 0 = no time limit
    uint64_t max_bytes;       // 0 = no size limit
} cbench_params;

typedef struct {
    uint64_t bytes;
    uint64_t ios;
    double   seconds;         // includes the final F_FULLFSYNC for writes
    int      error;           // 0 on success, errno otherwise; -100 if cancelled
} cbench_result;

typedef struct cbench_ctx cbench_ctx;   // opaque

cbench_ctx *cbench_ctx_create(void);
void        cbench_ctx_destroy(cbench_ctx *ctx);
void        cbench_ctx_cancel(cbench_ctx *ctx);                 // safe from any thread
uint64_t    cbench_ctx_progress_bytes(const cbench_ctx *ctx);   // atomic read

// Creates (or replaces) the file and actually fills it with random data, then F_FULLFSYNC.
int cbench_prepare_file(cbench_ctx *ctx, const char *path, uint64_t size);

// Runs ONE pass. If latencies_ns is not NULL and queue_depth == 1,
// records the latency of each I/O (at most latencies_cap values).
int cbench_run_pass(cbench_ctx *ctx, const char *path, const cbench_params *p,
                    cbench_result *out,
                    uint64_t *latencies_ns, uint64_t latencies_cap, uint64_t *latencies_count);

#endif /* CBENCHIO_H */
