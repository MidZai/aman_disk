import Foundation
import DiskHealthCore

/// Texts shared by several views (the others stay as close as possible to their view).
enum Strings {
    static let statusGood = L("Healthy", "En bonne santé")
    static let statusCaution = L("Needs attention", "À surveiller")
    static let statusBad = L("Likely failing", "Défaillance probable")
    static let statusUnknown = L("Health unknown", "Santé inconnue")

    static let fusionDriveMember = L("Part of a Fusion Drive", "Fait partie d'un Fusion Drive")

    // Drives without health data
    static let unsupportedTitle = L("This drive's health data isn't accessible", "Les données de santé de ce disque ne sont pas accessibles")
    static let unsupportedText1 = L("Its USB enclosure doesn't pass S.M.A.R.T. commands through to macOS. The drive works normally; only wear and temperature can't be seen.", "Son boîtier USB ne transmet pas les commandes S.M.A.R.T. à macOS. Le disque fonctionne normalement : seules l'usure et la température restent invisibles.")
    static let usbNoSmartTitle = L("Health data unavailable for this drive", "Santé non disponible pour ce disque")
    static let usbNoSmartText = L("This drive is connected via USB. macOS does not pass health information through most USB enclosures. This does not mean the drive has an issue.", "Ce disque est branché en USB. macOS ne transmet pas les informations de santé à travers la plupart des boîtiers USB. Cela ne veut pas dire que le disque a un problème.")
    static let learnMore = L("Learn More", "En savoir plus")
    static let bridgeChip = L("Bridge chip", "Puce pont")
    static let linkSpeed = L("Link speed", "Vitesse du lien")
    static let protocolLabel = L("Protocol", "Protocole")
    static let driveInformation = L("Drive Information", "Informations sur le disque")
    static let volumesAndPartitions = L("Volumes and partitions", "Volumes et partitions")
    static let noMountedVolumes = L("No mounted volumes", "Aucun volume monté")
    static let usbHelpTitle = L("S.M.A.R.T. & USB Enclosures", "S.M.A.R.T. et boîtiers USB")
    static let usbHelpSection1Title = L("What is a bridge chip?", "Qu'est-ce qu'une puce pont ?")
    static let usbHelpSection1Text = L("USB enclosures contain a bridge controller chip (such as JMicron, ASMedia, or Realtek) that converts SATA or NVMe commands to USB. Under macOS, most of these chips do not forward low-level S.M.A.R.T. commands without specialized drivers.", "Les boîtiers USB contiennent une puce passerelle (telle que JMicron, ASMedia ou Realtek) qui convertit les commandes SATA ou NVMe en USB standard. Sous macOS, la plupart de ces puces ne relaient pas les commandes S.M.A.R.T. de bas niveau sans pilote spécifique.")
    static let usbHelpSection2Title = L("Third-party drivers (SAT SMART Driver)", "Pilotes tiers (SAT SMART Driver)")
    static let usbHelpSection2Text = L("Some SATA enclosures can transmit S.M.A.R.T. data if a third-party open-source driver (such as the SAT SMART Driver) is installed by the user.", "Certains boîtiers SATA peuvent transmettre leurs données de santé lorsqu'un pilote tiers open source (comme le SAT SMART Driver) est installé par l'utilisateur.")
    static let usbHelpSection3Title = L("Thunderbolt / USB4 enclosures", "Boîtiers Thunderbolt / USB4")
    static let usbHelpSection3Text = L("External SSDs connected via Thunderbolt 3/4/5 or USB4 in PCIe mode attach directly to the PCIe bus and support full S.M.A.R.T. monitoring without any driver.", "Les disques SSD connectés via Thunderbolt 3/4/5 ou USB4 en mode PCIe sont reliés directement au bus PCIe et permettent une lecture S.M.A.R.T. intégrale sans aucun pilote.")
    static let usbHelpSection4Title = L("Help the project", "Aider le projet")
    static let usbHelpSection4Text = L("You can export a diagnostic report to help Aman expand its hardware compatibility database.", "Vous pouvez exporter un rapport de diagnostic pour aider Aman à enrichir sa base de compatibilité matérielle.")
    static let done = L("Done", "Fermer")
    static let exportDiagnostic = L("Export Diagnostic…", "Exporter le diagnostic…")

    static let sdCardReaderTitle = L("SD card reader", "Lecteur de carte SD")
    static let sdCardReaderText = L("This SD card reader doesn't provide health data. SD cards have no S.M.A.R.T. interface that macOS can access.", "Ce lecteur de carte SD ne fournit pas de données de santé. Les cartes SD n'ont pas d'interface S.M.A.R.T. accessible depuis macOS.")

    static let smartDisabledTitle = L("S.M.A.R.T. disabled", "S.M.A.R.T. désactivé")
    static let smartDisabledText = L("This drive supports S.M.A.R.T., but it's turned off. Without it, Aman Disk can't read the drive's health.", "Ce disque prend en charge S.M.A.R.T., mais la fonction est désactivée. Sans elle, Aman Disk ne peut pas lire la santé du disque.")
    static let smartEnableButton = L("Turn On S.M.A.R.T.…", "Activer S.M.A.R.T.…")
    static let smartEnableConfirmTitle = L("Turn on S.M.A.R.T. on this drive?", "Activer S.M.A.R.T. sur ce disque ?")
    static let smartEnableConfirmText = L("Aman Disk will send the drive a single command that turns on its health monitoring. Your data isn't touched, and nothing else is changed.", "Aman Disk va envoyer au disque une seule commande, qui active sa surveillance de santé. Vos données ne sont pas touchées, et rien d'autre n'est modifié.")
    static let smartEnabledNotice = L("S.M.A.R.T. was turned off on this drive. Aman Disk turned it on.", "S.M.A.R.T. était désactivé sur ce disque. Aman l'a activé.")
    static let smartEnableFailedTitle = L("Couldn't turn on S.M.A.R.T.", "Impossible d'activer S.M.A.R.T.")
    static func smartEnableFailedText(code: Int32) -> String {
        L("The drive refused the command (code \(code)). Try again; if the problem persists, export a diagnostic.", "Le disque a refusé la commande (code \(code)). Réessayez ; si le problème persiste, exportez un diagnostic.")
    }
    static let retry = L("Try Again", "Réessayer")

    static let virtualDiskTitle = L("Virtual disk", "Disque virtuel")
    static let virtualDiskText = L("This is a virtual disk provided by virtualization software. Its health depends on the host computer's real drive.", "Ce disque est virtuel : il est fourni par un logiciel de virtualisation. Sa santé dépend du disque réel de l'ordinateur hôte.")

    static let noSmartInterfaceTitle = L("Health not available", "Santé non disponible")
    static let noSmartInterfaceText = L("macOS doesn't expose any health interface for this drive. Export a diagnostic to help us support it.", "macOS n'expose aucune interface de santé pour ce disque. Exportez un diagnostic pour nous aider à le prendre en charge.")

    static let readErrorTitle = L("Read error", "Erreur de lecture")
    static func readErrorText(code: String) -> String {
        L("Reading health data failed (\(code)). Try again; if the problem persists, export a diagnostic.", "La lecture des données de santé a échoué (\(code)). Réessayez ; si le problème persiste, exportez un diagnostic.")
    }

    // Performance test
    static func benchConfirmMessage(volume: String, size: String, duration: String, maxWritten: String) -> String {
        L("Aman Disk will create a \(size) test file on “\(volume)”, read and write it, then delete it. Duration: \(duration). Data written: up to \(maxWritten). Quit apps that use the disk heavily for reliable results.", "Aman Disk va créer un fichier de test de \(size) sur « \(volume) », le lire et l'écrire, puis le supprimer. Durée : \(duration). Données écrites : \(maxWritten) au plus. Fermez les applications qui utilisent beaucoup le disque pour des résultats fiables.")
    }
    static let benchConfirmInternal = L("This is an internal drive. On most recent Macs it's soldered and can't be replaced. A test uses a tiny fraction of its endurance, but avoid running it over and over.", "Ce disque est interne. Sur la plupart des Mac récents, il est soudé et ne peut pas être remplacé. Un test consomme une part infime de son endurance, mais évitez de le lancer en boucle.")
    static func benchNoSpace(volume: String, size: String, required: String) -> String {
        L("Not enough free space: a \(size) file needs at least \(required) free on “\(volume)”. Choose a smaller size.", "Espace libre insuffisant : il faut au moins \(required) de libre sur « \(volume) » pour un fichier de \(size). Choisissez une taille plus petite.")
    }
    static func benchAccessDenied(volume: String) -> String {
        L("macOS didn't allow Aman Disk to write to “\(volume)”. You can allow it in System Settings › Privacy & Security › Files and Folders.", "macOS n'a pas autorisé Aman Disk à écrire sur « \(volume) ». Vous pouvez l'autoriser dans Réglages Système › Confidentialité et sécurité › Fichiers et dossiers.")
    }
    static let benchQuitWarning = L("A performance test is running. Quitting stops it and deletes the test file.", "Un test de performances est en cours. Quitter l'arrête et supprime le fichier de test.")
    static func benchStoppedTemp(temp: String) -> String {
        L("Test stopped: the drive reached \(temp) °C. Let it cool down before running it again.", "Test arrêté : le disque a atteint \(temp) °C. Laissez-le refroidir avant de relancer.")
    }
    static let benchCancelled = L("Test cancelled. The test file was deleted.", "Test annulé. Le fichier de test a été supprimé.")
    static let benchHelpVolume = L("Volume where the test file is created. The test measures the physical drive that holds this volume.", "Volume sur lequel le fichier de test est créé. Le test mesure le disque physique qui porte ce volume.")
    static let benchHelpProfile = L("Quick: 3 passes of 2 s. Standard: 5 passes of 5 s. Read only: writes the test file once, then only reads.", "Rapide : 3 passes de 2 s. Standard : 5 passes de 5 s. Lecture seule : écrit le fichier de test une seule fois, puis ne fait que des lectures.")
    static let benchHelpSize = L("Size of the test file. A larger file reduces the effect of the drive's caches, but writes more data.", "Taille du fichier de test. Un fichier plus grand limite l'effet des caches du disque, mais écrit davantage.")
    static let benchHelpValues = L("Each value is the best pass. Hover over a cell for the median and latency. 1 MB/s = 1,000,000 bytes per second.", "Valeur affichée : la meilleure passe. Survolez une case pour la médiane et la latence. 1 Mo/s = 1 000 000 octets par seconde.")
    static let benchHelpQD = L("Number of requests sent in parallel (queue depth). On macOS it's simulated with parallel threads, so results compare between Macs, not directly with tests run on Windows.", "Nombre de requêtes envoyées en parallèle (profondeur de file). Sur macOS, elle est simulée par des fils d'exécution parallèles : les résultats se comparent donc entre Mac, pas directement avec des tests faits sous Windows.")
}
