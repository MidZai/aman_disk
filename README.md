<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Branding/Aman-Disk-brand/logo/aman-disk-logo-sombre.svg">
  <source media="(prefers-color-scheme: light)" srcset="Branding/Aman-Disk-brand/logo/aman-disk-logo-clair.svg">
  <img alt="Aman Disk" src="Branding/Aman-Disk-brand/logo/aman-disk-logo-clair.svg" width="300">
</picture>

Une application macOS native (SwiftUI) permettant d'analyser la santé des disques NVMe, ATA et internes.

## Nouveautés de la v0.3.0
- Prise en charge des disques internes ATA / SATA et Apple PCIe AHCI.
- Prise en charge complète de toutes les situations de disques internes (Fusion Drive, Apple RAID, lecteurs de carte SD, disques virtuels, SMART désactivé, export de diagnostic).
- Intégration du soutien Ko-fi.

## Captures d'écran
![Mode clair](docs/screenshot-light.png)
![Mode sombre](docs/screenshot-dark.png)

## Soutenir le projet

Aman Disk est gratuit et open source. Si l'application vous est utile, vous pouvez soutenir son développement :

[![Soutenir sur Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/midzai)

## Test de performances (Benchmark)

Aman Disk 0.3.0 intègre un outil de test de performances du stockage :
- **Mesures** : Le test évalue les débits en lecture/écriture séquentielle (fichiers volumineux) et aléatoire (petits fichiers de 4K, représentatifs de l'usage système).
- **Meilleure passe** : Le logiciel affiche le résultat de la meilleure passe pour refléter le potentiel maximal du disque. La médiane est indiquée dans l'export.
- **QD (Queue Depth)** : Sur macOS, la profondeur de file est simulée par des threads parallèles. Les résultats sont comparables entre Mac.
- **Impact matériel** : L'interface calcule l'estimation du volume total de données qui sera écrit (par ex. 10 Gio) pour rassurer l'utilisateur sur l'endurance.
- **Nettoyage** : Les fichiers temporaires générés lors des tests sont toujours supprimés, même si le test est annulé manuellement ou en cas de crash (mécanisme de nettoyage automatique au lancement).
