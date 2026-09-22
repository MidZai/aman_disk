#ifndef CDISKIO_H_
#define CDISKIO_H_

// Returns 0 on success. out_buffer must be at least 512 bytes.
int cdiskio_read_nvme_smart(const char *bsd_name, unsigned char *out_buffer, int buffer_size);

// Returns 0 on success. out_buffer must be at least 4096 bytes.
int cdiskio_read_nvme_identify(const char *bsd_name, unsigned char *out_buffer, int buffer_size);

#endif /* CDISKIO_H_ */
