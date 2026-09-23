#ifndef CBENCHIO_H
#define CBENCHIO_H

#include <stdint.h>

typedef enum { CBENCH_SEQ = 0, CBENCH_RND = 1 } cbench_pattern;
typedef enum { CBENCH_READ = 0, CBENCH_WRITE = 1 } cbench_direction;

typedef struct {
    cbench_pattern   pattern;
    cbench_direction direction;
    uint32_t block_size;      // 1048576 ou 4096
    uint32_t queue_depth;     // nombre de fils, 1 à 64
    uint64_t file_size;       // multiple de block_size
    double   max_seconds;     // 0 = pas de limite de temps
    uint64_t max_bytes;       // 0 = pas de limite de volume
} cbench_params;

typedef struct {
    uint64_t bytes;
    uint64_t ios;
    double   seconds;         // F_FULLFSYNC final compris pour les écritures
    int      error;           // 0 si succès, sinon errno ; -100 si annulé
} cbench_result;

typedef struct cbench_ctx cbench_ctx;   // opaque

cbench_ctx *cbench_ctx_create(void);
void        cbench_ctx_destroy(cbench_ctx *ctx);
void        cbench_ctx_cancel(cbench_ctx *ctx);                 // sûr depuis n'importe quel fil
uint64_t    cbench_ctx_progress_bytes(const cbench_ctx *ctx);   // lecture atomique

// Crée (ou remplace) le fichier et le remplit réellement de données aléatoires, puis F_FULLFSYNC.
int cbench_prepare_file(cbench_ctx *ctx, const char *path, uint64_t size);

// Exécute UNE passe. Si latencies_ns n'est pas NULL et queue_depth == 1,
// enregistre la latence de chaque E/S (au plus latencies_cap valeurs).
int cbench_run_pass(cbench_ctx *ctx, const char *path, const cbench_params *p,
                    cbench_result *out,
                    uint64_t *latencies_ns, uint64_t latencies_cap, uint64_t *latencies_count);

#endif /* CBENCHIO_H */
