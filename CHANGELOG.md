# Journal des modifications

## 0.9.1

- **Activation de S.M.A.R.T.** : sur un disque SATA où S.M.A.R.T. est désactivé, Aman l'active une seule fois (réglage « Activer S.M.A.R.T. automatiquement s'il est désactivé », activé par défaut), puis relit le disque. L'activation est notée dans le journal du disque. En cas d'échec, le code d'erreur s'affiche avec un bouton « Réessayer » ; aucune nouvelle tentative automatique. Réglage désactivé : bouton « Activer S.M.A.R.T.… » avec confirmation.
- **Menu Aide** : « Voir les nouvelles versions… » ouvre la page des versions sur GitHub, sans vérification réseau dans l'app.
- Modèles de signalement sur GitHub.

## 0.9.0

Première version publique.

- **Santé NVMe et ATA/AHCI** : lecture S.M.A.R.T. des SSD NVMe, des SSD Apple PCIe AHCI et des disques SATA ; état « En bonne santé », « À surveiller » ou « Défaillance probable », anneau de santé et durée de vie restante quand le disque la fournit.
- **Attributs expliqués en français**, convertis dans leur unité, ou en hexadécimal brut à la demande.
- **Historique de température** : une mesure toutes les 30 s, 24 h en pleine résolution puis 30 jours en moyennes ; courbes sur 1 h, 24 h, 7 jours et 30 jours.
- **Test de performances** séquentiel et aléatoire ; le fichier de test est toujours supprimé.
- **Surveillance continue** et **barre des menus** : état et température de chaque disque interne ; l'app peut y rester quand la fenêtre est fermée.
- **Icône du Dock vivante** qui suit la santé du disque de démarrage.
- **Alertes** : changement d'état, surchauffe prolongée, durée de vie sous 50 %, 25 % ou 10 %.
- **Rapports** PDF, texte ou JSON, numéro de série masqué par défaut ; **export du diagnostic** pour les disques non reconnus.
- **Réglages** : langue (anglais, français), barre des menus, ouverture à la connexion, Dock, alertes, historique.
- Binaire universel (Apple Silicon et Intel), macOS 14 ou plus récent ; aucune connexion réseau.
