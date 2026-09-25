# Liste de vérification de publication (Release Checklist)

Ce document récapitule l'ensemble des vérifications manuelles à effectuer avant de publier une nouvelle version d'**Aman Disk**.

---

## 1. Environnements d'exécution et matériel

- [ ] **macOS 14 (Sonoma)** : lancement propre, affichage sans glitch, autorisations IOKit.
- [ ] **macOS 15 (Sequoia)** : lancement propre, compatibilité barre des menus et alertes système.
- [ ] **macOS le plus récent disponible** : validation des comportements AppKit et SwiftUI.
- [ ] **Architecture Mac Apple Silicon (arm64)** : exécution native sans couche Rosetta 2.
- [ ] **Architecture Mac Intel (x86_64)** : exécution fluide, prise en compte des disques AHCI/SATA internes.

---

## 2. Disques internes et surveillance continue

- [ ] **Lecture S.M.A.R.T. du disque interne** :
  - Détection automatique (Apple Fabric SSD / NVMe interne).
  - Statut de santé, pourcentage d'usure et température affichés correctement.
- [ ] **Historique et persistance** :
  - L'historique des températures et des mesures de santé s'affiche dès l'ouverture.
  - La persistance dans `~/Library/Application Support/io.github.aman-disk.AmanDisk/` fonctionne sans duplication ni perte.
- [ ] **Icône Dock et Barre des menus** :
  - L'icône du Dock reflète fidèlement la santé du disque de démarrage.
  - Le panneau de la barre des menus s'ouvre rapidement et liste les disques internes.

---

## 3. Disques externes et branchement à chaud

- [ ] **Branchement d'un disque externe (USB / Thunderbolt / boîtier NVMe)** :
  - Apparition immédiate dans la barre latérale sans redémarrage de l'application.
  - Identification correcte du protocole, de la vitesse du lien et de la puce pont le cas échéant.
  - Pour un boîtier Thunderbolt / USB4 NVMe : lecture S.M.A.R.T. complète.
  - Pour un disque USB avec SAT SMART Driver : lecture ATA S.M.A.R.T. fonctionnelle.
  - Pour un disque USB sans pilote S.M.A.R.T. : affichage de la carte explicative neutre et du bouton *En savoir plus*.
- [ ] **Débranchement à chaud (Hot-unplug)** :
  - Déconnexion d'un disque externe : bascule automatique sur le disque interne sans plantage ni blocage.
  - Aucune fausse alerte de défaillance émise lors d'un débranchement normal.
  - Affichage de la mention « Vu pour la dernière fois : [date] » pour le disque déconnecté.
- [ ] **Reconnexion** :
  - L'historique de santé et de performance est automatiquement retrouvé grâce à l'empreinte SHA-256.

---

## 4. Tests de performance (Benchmark)

- [ ] **Benchmark sur disque interne** :
  - Lancement d'un test rapide ou complet sur le volume principal.
  - Déroulement complet des passes lecture/écriture.
  - Nettoyage automatique du fichier temporaire de test (`DiskHealthBench-*.tmp`).
- [ ] **Benchmark sur disque externe** :
  - Sélection d'un volume externe monté et inscriptible.
  - Débit mesuré cohérent avec la vitesse maximale théorique du lien affichée sous les résultats.
- [ ] **Résilience en cas de déconnexion pendant le test** :
  - Débrancher le disque externe pendant une passe active.
  - Arrêt immédiat et propre avec le message « Disque déconnecté pendant le test ».
  - Aucun crash, aucune fuite mémoire, aucun fichier orphelin persistant.

---

## 5. Mode démonstration et internationalisation

- [ ] **Mode démo** :
  - Activation via le menu Développement ou argument CLI.
  - Tous les profils simulés (NVMe interne usé, Thunderbolt externe sain, disque USB non supporté, clé USB) s'affichent correctement.
- [ ] **Vérification des 18 langues prises en charge** :
  - Tester chaque langue au moins une fois (via le sélecteur intégré dans les Réglages ou `AppleLanguages`) :
    - Français (`fr`), Anglais (`en`), Allemand (`de`), Espagnol (`es`), Italien (`it`), Néerlandais (`nl`), Portugais brésilien (`pt-BR`),
    - Russe (`ru`), Ukrainien (`uk`), Polonais (`pl`), Turc (`tr`),
    - Arabe (`ar`) avec inversion correcte de l'interface RTL (Right-to-Left),
    - Chinois simplifié (`zh-Hans`), Chinois traditionnel (`zh-Hant`), Japonais (`ja`), Coréen (`ko`),
    - Hindi (`hi`), Vietnamien (`vi`).
  - Aucun texte tronqué, aucune clé brute non traduite.

---

## 6. Confidentialité et sécurité

- [ ] **Absence totale de connexion réseau** :
  - Aucune requête HTTP/HTTPS effectuée en arrière-plan.
  - Aucun appel analytique, télémétrie ou crash reporter externe.
- [ ] **Masquage des données sensibles** :
  - Numéros de série masqués par défaut (`<masqué>`).
  - Aucun numéro de série en clair stocké dans les fichiers d'historique ou de benchmark.
  - Export de rapport de compatibilité : exclusion stricte des noms de volumes, chemins `/Users/...` et nom de machine.

---

## 7. Paquetage, DMG et premier lancement

- [ ] **Construction du bundle Release** :
  - Exécuter `./scripts/bundle.sh --release` pour générer le binaire universel.
  - Vérifier que la version affichée dans la fenêtre « À propos » et `Info.plist` correspond exactement à la release.
- [ ] **Création du DMG** :
  - Vérifier la présence du lien symbolique vers `/Applications`.
  - Glisser-déposer dans `/Applications`.
- [ ] **Premier lancement** :
  - Ouverture fluide depuis `/Applications`.
  - Vérification du comportement Gatekeeper et consignes de premier lancement documentées.
- [ ] **Cask Homebrew** :
  - Mettre à jour le fichier `packaging/homebrew/aman-disk.rb` avec le SHA-256 final du fichier DMG publié.
