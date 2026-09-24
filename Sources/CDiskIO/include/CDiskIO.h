#ifndef CDISKIO_H_
#define CDISKIO_H_

// Aucune de ces fonctions ne modifie les données du disque. Seule cdiskio_enable_ata_smart change
// un réglage : elle active S.M.A.R.T. (jamais de désactivation).
// Toutes renvoient 0 en cas de succès, un code négatif (-1 à -6) ou un IOReturn sinon.

// NVMe. out_buffer : 512 octets pour le journal SMART, 4096 pour Identify.
int cdiskio_read_nvme_smart(const char *bsd_name, unsigned char *out_buffer, int buffer_size);
int cdiskio_read_nvme_identify(const char *bsd_name, unsigned char *out_buffer, int buffer_size);
// Journal SMART (512 octets) et Identify (4096 octets) avec une seule ouverture du pilote.
int cdiskio_read_nvme_all(const char *bsd_name, unsigned char *smart_buffer, unsigned char *identify_buffer);

// ATA / SATA / PCIe AHCI. Tampons de 512 octets. -6 : S.M.A.R.T. désactivé.
int cdiskio_read_ata_smart_data(const char *bsd_name, unsigned char *out, int size);
int cdiskio_read_ata_smart_thresholds(const char *bsd_name, unsigned char *out, int size);
int cdiskio_read_ata_identify(const char *bsd_name, unsigned char *out, int size);   // même si S.M.A.R.T. est désactivé
int cdiskio_read_ata_smart_status(const char *bsd_name, int *threshold_exceeded);          // 0 ou 1
// Les quatre lectures ci-dessus avec une seule ouverture du pilote.
int cdiskio_read_ata_snapshot(const char *bsd_name, unsigned char *smart_data, unsigned char *thresholds,
                              unsigned char *identify, int *threshold_exceeded);

// Active S.M.A.R.T. (SMARTEnableDisableOperations(true)) et rien d'autre.
int cdiskio_enable_ata_smart(const char *bsd_name);

#endif /* CDISKIO_H_ */
