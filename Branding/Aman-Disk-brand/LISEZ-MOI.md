# Aman Disk — kit de logo

## Couleurs
- Encre (fond de l'icône) : #0B2230
- Eau (jauge) : #2E9FD6
- Gris texte sur clair : #55646E · sur sombre : #9AA8B2
- Alertes (icône vivante) : orange #E8A33D · rouge #E5534B

Police du logo : Jost (SemiBold pour « aman », Regular pour « disk »), licence OFL.
Dans les SVG du logo, le texte est vectorisé : aucune police à installer.

## Dossiers
- icone-app/ : AppIcon.appiconset (à glisser dans Assets.xcassets de Xcode), AppIcon.icns, SVG et PNG 1024 sur la grille Apple
- calques-icon-composer/ : 3 calques séparés (1024 px) pour Icon Composer ; mettre #0B2230 comme couleur de fond
- barre-des-menus/ : icône « template » noire pour la barre des menus (macOS l'inverse seul en mode sombre)
- logo/ : logo complet, versions fond clair et fond sombre (SVG + PNG @2x)
- web/ : favicon, icônes du site, avatar carré pour GitHub et Ko-fi

La jauge est figée à 80 % dans tous les fichiers.

## États de santé (etats-sante/)
Une icône par palier de 5 %, de 100 % à 5 % (fichiers aman-100 … aman-005).
- 60 à 100 % : bleu #2E9FD6 (bon)
- 30 à 55 % : orange #E8A33D (prudence)
- 5 à 25 % : rouge #E5534B (critique)
Pour une valeur intermédiaire, arrondir au palier de 5 % inférieur.
Les versions barre des menus (template noir) existent pour chaque palier.
