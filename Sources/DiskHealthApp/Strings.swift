import Foundation

enum Strings {
    static let appName = "Aman Disk"
    static let refresh = "Actualiser"
    static let copyReport = "Copier le rapport"
    static let history = "Historique"
    static let health = "santé"
    static let statusGood = "En bonne santé"
    static let statusCaution = "À surveiller"
    static let statusBad = "Défaillance probable"
    static let statusUnknown = "Santé inconnue"
    
    static let tileTemperature = "Température"
    static let tileTemperatureHelp = "Dernière heure, max 44 °C"
    static let tileDataWritten = "Données écrites"
    static let tileLifeLeft = "Durée de vie restante"
    static let tileLifeLeftHelp = "Estimation disponible après 7 jours"
    
    static let infoTitle = "Informations"
    static let infoCapacity = "Capacité"
    static let infoInterface = "Interface"
    static let infoFirmware = "Firmware"
    static let infoSerial = "Numéro de série"
    static let infoPowerOnHours = "Heures d'allumage"
    static let infoPowerCycles = "Cycles d'allumage"
    static let infoUnsafeShutdowns = "Arrêts non propres"
    static let infoMediaErrors = "Erreurs média"
    static let actionShow = "Afficher"
    static let actionHide = "Masquer"
    
    static let smartTitle = "Journal SMART / Health"
    static let smartColId = "ID"
    static let smartColAttr = "Attribut"
    static let smartColRaw = "Brut"
    static let smartColValue = "Valeur"
    
    static let attr01 = "Avertissement critique"
    static let attr02 = "Température composite"
    static let attr03 = "Réserve disponible"
    static let attr04 = "Seuil de réserve"
    static let attr05 = "Pourcentage utilisé"
    static let attr06 = "Données lues"
    static let attr07 = "Données écrites"
    static let attr08 = "Commandes de lecture"
    static let attr09 = "Commandes d'écriture"
    static let attr0A = "Temps d'activité du contrôleur"
    static let attr0B = "Cycles d'allumage"
    static let attr0C = "Heures d'allumage"
    static let attr0D = "Arrêts non propres"
    static let attr0E = "Erreurs média et intégrité"
    static let attr0F = "Entrées du journal d'erreurs"
    
    static let unsupportedTitle = "Les données de santé de ce disque ne sont pas accessibles"
    static let unsupportedText1 = "Son boîtier USB ne transmet pas les commandes SMART à macOS. Le disque fonctionne normalement : seules l'usure et la température restent invisibles."
    static let unsupportedText2 = "Exportez un diagnostic anonymisé et joignez-le à une demande sur GitHub. Chaque boîtier documenté peut être pris en charge dans une prochaine version."
    static let exportDiagnostic = "Exporter le diagnostic…"
    static let viewSupported = "Voir les boîtiers pris en charge"
    
    // Phase F
    static let sdCardReaderTitle = "Lecteur de carte SD"
    static let sdCardReaderText = "Ce lecteur de carte SD ne fournit pas de données de santé. Les cartes SD n'ont pas d'interface S.M.A.R.T. accessible depuis macOS."
    
    static let smartDisabledTitle = "S.M.A.R.T. désactivé"
    static let smartDisabledText = "Ce disque prend en charge S.M.A.R.T., mais la fonction est désactivée. Aman Disk ne modifie jamais les réglages d'un disque."
    
    static let virtualDiskTitle = "Disque virtuel"
    static let virtualDiskText = "Ce disque est virtuel : il est fourni par un logiciel de virtualisation. Sa santé dépend du disque réel de l'ordinateur hôte."
    
    static let noSmartInterfaceTitle = "Santé non disponible"
    static let noSmartInterfaceText = "macOS n'expose aucune interface de santé pour ce disque. Exportez un diagnostic pour nous aider à le prendre en charge."
    
    static let readErrorTitle = "Erreur de lecture"
    static func readErrorText(code: String) -> String {
        "La lecture des données de santé a échoué (\(code)). Réessayez ; si le problème persiste, exportez un diagnostic."
    }
    
    static let fusionDriveMember = "Fait partie d'un Fusion Drive"
    
    // Benchmark Strings
    static func benchConfirmMessage(volume: String, size: String, duration: String, maxWritten: String) -> String {
        return "Aman Disk va créer un fichier de test de \(size) sur « \(volume) », le lire et l'écrire, puis le supprimer. Durée estimée : \(duration). Données écrites au plus : \(maxWritten). Fermez les applications qui utilisent beaucoup le disque pour des résultats fiables."
    }
    static let benchConfirmInternal = "Ce disque est interne. Sur la plupart des Mac récents, il est soudé et ne peut pas être remplacé. Un test consomme une part infime de son endurance, mais évitez de le lancer en boucle."
    static func benchNoSpace(volume: String, size: String, required: String) -> String {
        return "Espace libre insuffisant : il faut au moins \(required) de libre sur « \(volume) » pour un fichier de \(size). Choisissez une taille plus petite."
    }
    static func benchAccessDenied(volume: String) -> String {
        return "macOS n'a pas autorisé Aman Disk à écrire sur « \(volume) ». Vous pouvez l'autoriser dans Réglages Système › Confidentialité et sécurité › Fichiers et dossiers."
    }
    static let benchQuitWarning = "Un test de performances est en cours. Quitter l'arrête et supprime le fichier de test."
    static func benchStoppedTemp(temp: String) -> String {
        return "Test arrêté : le disque a atteint \(temp) °C. Laissez-le refroidir avant de relancer."
    }
    static let benchCancelled = "Test annulé. Le fichier de test a été supprimé."
    static let benchHelpVolume = "Volume sur lequel le fichier de test est créé. Le test mesure le disque physique qui porte ce volume."
    static let benchHelpProfile = "Rapide : 3 passes de 2 s. Standard : 5 passes de 5 s. Lecture seule : écrit le fichier de test une seule fois, puis ne fait que des lectures."
    static let benchHelpSize = "Taille du fichier de test. Un fichier plus grand limite l'effet des caches du disque, mais écrit davantage."
    static let benchHelpValues = "Valeur affichée : la meilleure passe. La médiane de toutes les passes figure dans le rapport."
    static let benchHelpQD = "QD (profondeur de file) : nombre de requêtes envoyées en parallèle. Sur macOS, elle est simulée par des fils d'exécution parallèles. Les résultats sont comparables entre Mac, pas directement avec des tests faits sous Windows."
}
