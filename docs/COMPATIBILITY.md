# Compatibilité du matériel externe (USB & Thunderbolt)

Ce document répertorie la compatibilité des boîtiers externes, disques USB et boîtiers Thunderbolt avec **Aman Disk** sous macOS.

## Contexte technique

- **Thunderbolt 3 / 4 / 5 et USB4 (PCIe)** : Le disque NVMe est relié directement aux lignes PCIe de macOS. La lecture S.M.A.R.T. intégrale fonctionne nativement **sans aucun pilote tiers**.
- **USB standard (SATA / NVMe)** : macOS ne transmet pas les commandes S.M.A.R.T. de bas niveau à travers la majorité des puces ponts USB. Le disque fonctionne normalement, mais ses données d'usure et sa température restent inaccessibles par défaut.
- **SAT SMART Driver (pilote tiers optionnel)** : Pour les boîtiers USB SATA compatibles qui supportent la traduction SAT (SCSI/ATA Translation), l'installation manuelle par l'utilisateur du pilote open source tiers *OS-X-SAT-SMART-Driver* permet à Aman Disk de lire le S.M.A.R.T. ATA. *Attention : nécessite la sécurité réduite sur Apple Silicon et ne gère pas le NVMe.*

---

## Tableau de compatibilité

| Boîtier / Modèle | Puce pont | Type (SATA / NVMe) | S.M.A.R.T. sans pilote | Avec SAT SMART Driver | Testé par | Notes |
| :--- | :--- | :--- | :---: | :---: | :--- | :--- |
| *Exemple : OWC Envoy Pro FX* | *Intel Titan Ridge* | *NVMe (PCIe)* | ✅ Oui | N/A | MidZai | Thunderbolt 3 natif, santé complète |
| *Exemple : Crucial X8* | *ASMedia ASM2362* | *NVMe (USB)* | ❌ Non | ❌ Non | MidZai | Puce USB NVMe, bridge USB standard |
| *Exemple : Orico 2.5" SATA* | *JMicron JMS578* | *SATA* | ❌ Non | ✅ Oui | MidZai | Rebranchement requis après boot |
| | | | | | | |
| | | | | | | |
| | | | | | | |
| | | | | | | |

*Légende :*
- ✅ **Oui** : Données de santé S.M.A.R.T. lisibles et affichées dans Aman Disk.
- ❌ **Non** : Données de santé non transmises par le contrôleur sous macOS.
- **N/A** : Non applicable (ex: boîtier NVMe avec un pilote SATA).

---

## Comment contribuer et tester votre matériel

Midou n'a pas tous les boîtiers du marché ! Vous pouvez aider la communauté en envoyant un rapport de compatibilité anonymisé :

1. Branchez votre disque externe sur votre Mac.
2. Ouvrez **Aman Disk**.
3. Sélectionnez le disque et choisissez **Exporter un rapport de compatibilité…** :
   - Depuis le menu **Aide** › **Exporter un rapport de compatibilité…**
   - Depuis le menu **Disque** › **Exporter un rapport de compatibilité…**
   - Ou par un **clic droit** sur le disque dans la barre latérale.
4. Enregistrez le fichier JSON sur votre Mac. Aucune donnée personnelle n'est incluse (numéros de série masqués, aucun nom de volume, aucun nom d'utilisateur ni de machine).
5. Ouvrez un ticket GitHub avec le [Modèle de rapport de compatibilité USB](https://github.com/MidZai/aman_disk/issues/new?template=usb-compatibility.yml) et joignez votre fichier JSON.
6. Le tableau ci-dessus sera mis à jour avec vos résultats !
