//
// Localisation.swift — la seule porte vers le catalogue de chaînes.
//
// POURQUOI DES `.lproj` ET PAS UN STRING CATALOG. Le `.xcstrings` est la voie Apple depuis
// Xcode 15, mais il n'est PAS compilé par `swift build` : il faut `xcstringstool`, qui
// n'appartient qu'au système de construction d'Xcode. MESURÉ sur un package jumeau — le
// `.xcstrings` est recopié tel quel dans le bundle, `Bundle.module.localizations` rend `[]`,
// et chaque clé revient telle quelle. C'est très exactement le bug invisible : rien ne casse,
// l'interface affiche « menu.settings ». Un dépôt sans Xcode ne peut donc pas s'en servir.
// Les `.lproj/Localizable.strings`, eux, sont compris par SwiftPM : avec
// `defaultLocalization: "en"` au manifeste, `Bundle.module.localizations` rend les huit langues.
//
// POURQUOI TOUT LE CATALOGUE VIT DANS BouncerCore. `Bundle.module` est propre à une target :
// deux catalogues voudraient dire deux bundles, deux fichiers à tenir en parité, et la même
// phrase écrite deux fois. Le catalogue vit donc dans la bibliothèque, que la target
// exécutable importe déjà, et `catalogueDeChaines` est l'unique bundle des deux côtés.
//
// POURQUOI LA LANGUE SE CHOISIT ICI ET PAS PAR `AppleLanguages` SEUL. Foundation fige la langue
// d'un processus à son lancement : écrire `AppleLanguages` ne change rien avant la relance. Or
// la consigne est que l'app parte en anglais quelle que soit la machine, et que le choix de
// l'utilisateur s'applique sans relancer. `texte` lit donc le `.lproj` de la langue choisie
// directement — un `.lproj` est un bundle comme un autre — et `AppleLanguages` n'est écrit
// qu'en plus, pour que ce que macOS fournit lui-même (le titre de la fenêtre Réglages) suive à
// la relance suivante.

import Foundation

/// La langue de l'interface, telle que l'utilisateur la choisit dans les réglages.
///
/// Les `rawValue` sont les noms des dossiers `.lproj` — c'est la seule chose qui les relie,
/// et `CatalogueDeChainesTests` vérifie que chaque cas a bien son dossier dans le bundle.
public enum LangueInterface: String, CaseIterable, Identifiable, Sendable {
    /// Celle de macOS. Ce n'est PAS le défaut : l'app part en anglais (cf. `Reglages.langue`).
    case systeme = "system"
    case en, fr, es, de
    case ptBR = "pt_br"
    case zhHans = "zh_hans"
    case ja, ko

    public var id: String { rawValue }

    /// Le nom du dossier `.lproj`, `nil` pour laisser macOS choisir.
    public var code: String? { self == .systeme ? nil : rawValue }

    /// Le nom de la langue écrit DANS cette langue. Un menu de langues se lit ainsi quel que soit
    /// l'état de l'app : un utilisateur coréen tombé sur une interface en allemand doit pouvoir
    /// retrouver « 한국어 » sans lire l'allemand. L'entrée « système », elle, est traduite.
    public var nomNatif: String {
        switch self {
        case .systeme: return texte("settings.general.language.system")
        case .en: return "English"
        case .fr: return "Français"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .ptBR: return "Português (Brasil)"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }
}

/// Le bundle de ressources de BouncerCore, exposé aux deux targets.
///
/// La target exécutable n'a pas de `Bundle.module` à elle : elle ne porte aucune ressource, et
/// `Bundle.main` d'une app est le bundle de l'app, pas celui du package.
///
/// POURQUOI ON NE SE CONTENTE PAS DE `Bundle.module`. L'accesseur que SwiftPM génère cherche à
/// DEUX endroits : à côté de `Bundle.main.bundleURL`, puis — en repli — au chemin ABSOLU du
/// dossier `.build` de la machine qui a compilé. Sur une app packagée, le premier chemin vaut
/// `Bouncer.app/Bouncer_BouncerCore.bundle`, à la racine du bundle, là où rien n'a le droit de
/// vivre : la signature de code veut tout dans `Contents/`. Le second, lui, N'EXISTE QUE SUR LA
/// MACHINE DE BUILD — d'où un défaut qui ne se voit jamais chez le développeur et qui fait un
/// `fatalError` chez le premier utilisateur, au premier menu ouvert. VÉRIFIÉ : `.build` déplacé,
/// l'app packagée s'arrêtait net.
///
/// On cherche donc d'abord dans `Contents/Resources`, où `build.sh` pose le bundle, et
/// `Bundle.module` ne sert plus qu'à `swift test` et `swift run`, où son chemin `.build` est bon.
public let catalogueDeChaines: Bundle = {
    let nom = "Bouncer_BouncerCore.bundle"
    if let racine = Bundle.main.resourceURL,
       let bundle = Bundle(url: racine.appendingPathComponent(nom)) {
        return bundle
    }
    return .module
}()

/// Le `.lproj` de chaque langue ouvert comme un bundle à part entière : les chaînes y sont à
/// la racine, donc `localizedString` les trouve sans passer par la résolution de Foundation.
/// Pour `.systeme`, c'est le catalogue entier, et Foundation choisit d'après `AppleLanguages`.
/// Construit une fois pour toutes — un `let` global s'initialise sans course — plutôt qu'un
/// cache qui se remplirait sous des lectures concurrentes.
private let bundlesParLangue: [LangueInterface: Bundle] = Dictionary(
    uniqueKeysWithValues: LangueInterface.allCases.map { langue in
        guard let code = langue.code,
              let url = catalogueDeChaines.url(forResource: code, withExtension: "lproj"),
              let bundle = Bundle(url: url)
        else { return (langue, catalogueDeChaines) }
        return (langue, bundle)
    }
)

/// La langue en cours. Écrite par `activerLangue` seulement, lue par `texte`. Ce n'est pas la
/// source de vérité — c'est `Reglages.langue`, persistée — mais c'est la copie que chaque
/// `texte(...)` consulte sans repasser par `UserDefaults`.
private var langueActive: LangueInterface = .en

/// Fait de `langue` celle de toutes les chaînes à venir, sans relance. `Reglages.langue` est le
/// seul appelant ; c'est lui qui persiste le choix. Les tests n'y touchent pas : ils passent
/// par `chaine(_:langue:)`, qui ne dépend d'aucun état, parce qu'une suite qui bascule la langue
/// pendant qu'une autre compare deux `texte(...)` rendrait la seconde fausse une fois sur mille.
public func activerLangue(_ langue: LangueInterface) {
    langueActive = langue
}

/// La locale qui va avec une langue : celle de la LANGUE CHOISIE, pas celle de la machine. La
/// règle de pluriel du français range 0 avec le singulier, et « 1 notch app found » pour zéro
/// app serait un mensonge en anglais.
private func locale(_ langue: LangueInterface) -> Locale {
    langue.code.map(Locale.init(identifier:)) ?? .current
}

/// La chaîne d'une clé dans une langue donnée. La forme sans état, sous `texte`.
///
/// La valeur de repli est la clé elle-même : c'est ce que fait Foundation, et c'est visible à
/// l'œil nu dans l'interface. `CatalogueDeChainesTests` interdit qu'une clé arrive jusque-là.
public func chaine(_ cle: String, langue: LangueInterface) -> String {
    (bundlesParLangue[langue] ?? catalogueDeChaines).localizedString(forKey: cle, value: nil, table: nil)
}

/// Une chaîne à trous dans une langue donnée. Les arguments sont numérotés dans le catalogue
/// (`%1$@`, `%2$d`) : une traduction a le droit de les remettre dans un autre ordre.
public func chaine(_ cle: String, langue: LangueInterface, _ arguments: [CVarArg]) -> String {
    String(format: chaine(cle, langue: langue), locale: locale(langue), arguments: arguments)
}

/// Une chaîne au pluriel dans une langue donnée, résolue par son `.stringsdict`.
public func chainePlurielle(_ cle: String, _ nombre: Int, langue: LangueInterface) -> String {
    String(format: chaine(cle, langue: langue), locale: locale(langue), nombre)
}

/// Une chaîne visible par l'utilisateur, dans la langue active.
public func texte(_ cle: String) -> String {
    chaine(cle, langue: langueActive)
}

/// Une chaîne à trous, dans la langue active.
public func texte(_ cle: String, _ arguments: CVarArg...) -> String {
    chaine(cle, langue: langueActive, arguments)
}

/// Une chaîne au pluriel, dans la langue active.
///
/// Séparée de `texte(_:_:)` pour que le point d'appel dise qu'il y a une règle de pluriel —
/// une clé de `.stringsdict` absente du `.strings` ne se voit pas autrement.
public func texteAuPluriel(_ cle: String, _ nombre: Int) -> String {
    chainePlurielle(cle, nombre, langue: langueActive)
}
