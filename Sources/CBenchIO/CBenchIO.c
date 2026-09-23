#include "CBenchIO.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/stat.h>
#include <errno.h>
#include <time.h>
#include <string.h>

struct cbench_ctx {
    _Atomic int cancelled;
    _Atomic uint64_t progress_bytes;
};

cbench_ctx *cbench_ctx_create(void) {
    cbench_ctx *ctx = calloc(1, sizeof(cbench_ctx));
    atomic_init(&ctx->cancelled, 0);
    atomic_init(&ctx->progress_bytes, 0);
    return ctx;
}

void cbench_ctx_destroy(cbench_ctx *ctx) {
    if (ctx) free(ctx);
}

void cbench_ctx_cancel(cbench_ctx *ctx) {
    if (ctx) atomic_store(&ctx->cancelled, 1);
}

uint64_t cbench_ctx_progress_bytes(const cbench_ctx *ctx) {
    if (!ctx) return 0;
    return atomic_load(&ctx->progress_bytes);
}

// XorShift64* PRNG
static inline uint64_t xorshift64star(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * 0x2545F4914F6CDD1DULL;
}

int cbench_prepare_file(cbench_ctx *ctx, const char *path, uint64_t size) {
    atomic_store(&ctx->progress_bytes, 0);
    int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) return errno;

    fcntl(fd, F_NOCACHE, 1);
    
    size_t block_size = 1048576; // 1 MiB chunks
    void *buf = NULL;
    if (posix_memalign(&buf, 4096, block_size) != 0) {
        close(fd);
        return ENOMEM;
    }

    uint64_t written = 0;
    int err = 0;
    while (written < size) {
        if (atomic_load(&ctx->cancelled)) {
            err = -100;
            break;
        }
        arc4random_buf(buf, block_size);
        
        uint64_t to_write = size - written;
        if (to_write > block_size) to_write = block_size;
        
        size_t chunk_written = 0;
        while (chunk_written < to_write) {
            if (atomic_load(&ctx->cancelled)) {
                err = -100;
                break;
            }
            ssize_t res = pwrite(fd, (char *)buf + chunk_written, to_write - chunk_written, written + chunk_written);
            if (res < 0) {
                if (errno == EINTR) continue;
                err = errno;
                break;
            }
            if (res == 0) {
                err = EIO;
                break;
            }
            chunk_written += res;
        }
        if (err != 0) break;
        
        written += to_write;
        atomic_fetch_add(&ctx->progress_bytes, to_write);
    }
    
    if (err == 0) {
        if (fcntl(fd, F_FULLFSYNC) == -1) {
            err = errno;
        }
    }
    
    free(buf);
    close(fd);
    
    if (err == 0) {
        struct stat st;
        if (stat(path, &st) == 0) {
            if (st.st_blocks * 512 < size) {
                err = EIO;
            }
        } else {
            err = errno;
        }
    }
    
    return err;
}

typedef struct {
    cbench_ctx *ctx;
    int fd;
    const cbench_params *params;
    void *buf;
    uint64_t rng_state;
    
    // Coordination
    _Atomic int *ready_count;
    int total_threads;
    pthread_mutex_t *start_mutex;
    pthread_cond_t *start_cond;
    _Atomic int *start_flag;
    
    // Shared state for SEQ
    _Atomic uint64_t *shared_block_idx;
    
    // Output
    uint64_t bytes;
    uint64_t ios;
    int error;
    
    // Latencies
    uint64_t *latencies_ns;
    uint64_t latencies_cap;
    uint64_t latencies_count;
    
    // Time tracking for limits
    uint64_t start_time_ns;
    
} thread_arg;

static void *thread_func(void *arg_void) {
    thread_arg *arg = (thread_arg *)arg_void;
    
    // Wait for all threads to be ready
    pthread_mutex_lock(arg->start_mutex);
    atomic_fetch_add(arg->ready_count, 1);
    while (atomic_load(arg->start_flag) == 0) {
        pthread_cond_wait(arg->start_cond, arg->start_mutex);
    }
    pthread_mutex_unlock(arg->start_mutex);
    
    uint64_t max_ns = (uint64_t)(arg->params->max_seconds * 1000000000.0);
    
    while (1) {
        if (atomic_load(&arg->ctx->cancelled)) {
            arg->error = -100;
            break;
        }
        
        uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        if (max_ns > 0 && now - arg->start_time_ns >= max_ns) {
            break;
        }
        
        if (arg->params->max_bytes > 0 && arg->bytes >= arg->params->max_bytes) {
            break;
        }
        
        uint64_t offset;
        if (arg->params->pattern == CBENCH_SEQ) {
            uint64_t block_idx = atomic_fetch_add(arg->shared_block_idx, 1);
            offset = block_idx * arg->params->block_size;
            
            if (offset >= arg->params->file_size) {
                if (arg->params->direction == CBENCH_WRITE || max_ns == 0) {
                    // For SEQ write, or if no time limit, we stop exactly at file_size.
                    break;
                } else {
                    // SEQ read with time limit loops back
                    uint64_t total_blocks = arg->params->file_size / arg->params->block_size;
                    if (total_blocks == 0) break;
                    offset = (block_idx % total_blocks) * arg->params->block_size;
                }
            }
        } else {
            // RND
            uint64_t total_blocks = arg->params->file_size / arg->params->block_size;
            if (total_blocks == 0) break;
            uint64_t block_idx = xorshift64star(&arg->rng_state) % total_blocks;
            offset = block_idx * arg->params->block_size;
        }
        
        uint64_t io_start = 0;
        if (arg->latencies_ns != NULL && arg->latencies_count < arg->latencies_cap) {
            io_start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        }
        
        size_t chunk_done = 0;
        int io_err = 0;
        while (chunk_done < arg->params->block_size) {
            if (atomic_load(&arg->ctx->cancelled)) {
                io_err = -100;
                break;
            }
            
            ssize_t res;
            if (arg->params->direction == CBENCH_WRITE) {
                res = pwrite(arg->fd, (char *)arg->buf + chunk_done, arg->params->block_size - chunk_done, offset + chunk_done);
            } else {
                res = pread(arg->fd, (char *)arg->buf + chunk_done, arg->params->block_size - chunk_done, offset + chunk_done);
            }
            
            if (res < 0) {
                if (errno == EINTR) continue;
                io_err = errno;
                break;
            }
            if (res == 0) {
                io_err = EIO;
                break;
            }
            chunk_done += res;
        }
        
        if (io_err != 0) {
            arg->error = io_err;
            break;
        }
        
        arg->bytes += arg->params->block_size;
        arg->ios += 1;
        atomic_fetch_add(&arg->ctx->progress_bytes, arg->params->block_size);
        
        if (io_start > 0 && arg->latencies_ns != NULL && arg->latencies_count < arg->latencies_cap) {
            uint64_t io_end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            arg->latencies_ns[arg->latencies_count++] = io_end - io_start;
        }
    }
    
    return NULL;
}

int cbench_run_pass(cbench_ctx *ctx, const char *path, const cbench_params *p,
                    cbench_result *out,
                    uint64_t *latencies_ns, uint64_t latencies_cap, uint64_t *latencies_count) {
    if (!ctx || !path || !p || !out) return EINVAL;
    
    atomic_store(&ctx->progress_bytes, 0);
    out->bytes = 0;
    out->ios = 0;
    out->seconds = 0;
    out->error = 0;
    if (latencies_count) *latencies_count = 0;
    
    int flags = (p->direction == CBENCH_WRITE) ? O_WRONLY : O_RDONLY;
    int fd = open(path, flags);
    if (fd < 0) return errno;
    
    fcntl(fd, F_NOCACHE, 1);
    fcntl(fd, F_RDAHEAD, 0);
    
    int num_threads = p->queue_depth;
    if (num_threads < 1) num_threads = 1;
    if (num_threads > 64) num_threads = 64;
    
    pthread_t threads[64];
    thread_arg args[64];
    void *bufs[64] = {NULL};
    
    int setup_err = 0;
    for (int i = 0; i < num_threads; i++) {
        if (posix_memalign(&bufs[i], 4096, p->block_size) != 0) {
            setup_err = ENOMEM;
            break;
        }
        if (p->direction == CBENCH_WRITE) {
            arc4random_buf(bufs[i], p->block_size);
        }
    }
    
    if (setup_err != 0) {
        for (int i = 0; i < num_threads; i++) {
            if (bufs[i]) free(bufs[i]);
        }
        close(fd);
        return setup_err;
    }
    
    _Atomic int ready_count = 0;
    pthread_mutex_t start_mutex = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t start_cond = PTHREAD_COND_INITIALIZER;
    _Atomic int start_flag = 0;
    _Atomic uint64_t shared_block_idx = 0;
    
    for (int i = 0; i < num_threads; i++) {
        args[i].ctx = ctx;
        args[i].fd = fd;
        args[i].params = p;
        args[i].buf = bufs[i];
        
        // Ensure non-zero seed
        do {
            arc4random_buf(&args[i].rng_state, sizeof(uint64_t));
        } while (args[i].rng_state == 0);
        
        args[i].ready_count = &ready_count;
        args[i].total_threads = num_threads;
        args[i].start_mutex = &start_mutex;
        args[i].start_cond = &start_cond;
        args[i].start_flag = &start_flag;
        args[i].shared_block_idx = &shared_block_idx;
        
        args[i].bytes = 0;
        args[i].ios = 0;
        args[i].error = 0;
        
        if (latencies_ns && num_threads == 1) {
            args[i].latencies_ns = latencies_ns;
            args[i].latencies_cap = latencies_cap;
        } else {
            args[i].latencies_ns = NULL;
            args[i].latencies_cap = 0;
        }
        args[i].latencies_count = 0;
        
        pthread_create(&threads[i], NULL, thread_func, &args[i]);
    }
    
    // Wait for all threads to be ready
    while (atomic_load(&ready_count) < num_threads) {
        usleep(100);
    }
    
    uint64_t t_start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    
    for (int i = 0; i < num_threads; i++) {
        args[i].start_time_ns = t_start;
    }
    
    pthread_mutex_lock(&start_mutex);
    atomic_store(&start_flag, 1);
    pthread_cond_broadcast(&start_cond);
    pthread_mutex_unlock(&start_mutex);
    
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }
    
    int final_err = 0;
    for (int i = 0; i < num_threads; i++) {
        if (args[i].error != 0 && final_err == 0) {
            final_err = args[i].error;
        }
        out->bytes += args[i].bytes;
        out->ios += args[i].ios;
        if (latencies_count && num_threads == 1) {
            *latencies_count = args[i].latencies_count;
        }
    }
    
    if (final_err == 0 && p->direction == CBENCH_WRITE) {
        if (fcntl(fd, F_FULLFSYNC) == -1) {
            final_err = errno;
        }
    }
    
    uint64_t t_end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    out->seconds = (double)(t_end - t_start) / 1000000000.0;
    out->error = final_err;
    
    for (int i = 0; i < num_threads; i++) {
        free(bufs[i]);
    }
    close(fd);
    
    return final_err;
}
