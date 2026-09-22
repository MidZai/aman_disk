#ifndef CDISKIO_H_
#define CDISKIO_H_

// Returns 0 on success. out_buffer must be at least 512 bytes.
int cdiskio_read_nvme_smart(const char *bsd_name, unsigned char *out_buffer, int buffer_size);

// Returns 0 on success. out_buffer must be at least 4096 bytes.
int cdiskio_read_nvme_identify(const char *bsd_name, unsigned char *out_buffer, int buffer_size);

// Toutes renvoient 0 en cas de succès. Mêmes codes d'erreur que pour le NVMe (-1 à -5).
int cdiskio_read_ata_smart_data(const char *bsd_name, unsigned char *out, int size);       // 512 octets
int cdiskio_read_ata_smart_thresholds(const char *bsd_name, unsigned char *out, int size); // 512 octets
int cdiskio_read_ata_identify(const char *bsd_name, unsigned char *out, int size);         // 512 octets
int cdiskio_read_ata_smart_status(const char *bsd_name, int *threshold_exceeded);          // 0 ou 1

#endif /* CDISKIO_H_ */
