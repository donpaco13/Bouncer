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
// `defaultLocalization: "en"` au manifeste, `Bundle.module.localizations` rend `["en", "fr"]`.
//
// POURQUOI TOUT LE CATALOGUE VIT DANS BouncerCore. `Bundle.module` est propre à une target :
// deux catalogues voudraient dire deux bundles, deux fichiers à tenir en parité, et la même
// phrase écrite deux fois. Le catalogue vit donc dans la bibliothèque, que la target
// exécutable importe déjà, et `catalogueDeChaines` est l'unique bundle des deux côtés.

import Foundation

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

/// Une chaîne visible par l'utilisateur, lue dans le catalogue.
///
/// La valeur de repli est la clé elle-même : c'est ce que fait Foundation, et c'est visible à
/// l'œil nu dans l'interface. `CatalogueDeChainesTests` interdit qu'une clé arrive jusque-là.
public func texte(_ cle: String) -> String {
    catalogueDeChaines.localizedString(forKey: cle, value: nil, table: nil)
}

/// Une chaîne à trous. Les arguments sont numérotés dans le catalogue (`%1$@`, `%2$d`) : une
/// traduction a le droit de les remettre dans un autre ordre, et le français le fait déjà.
public func texte(_ cle: String, _ arguments: CVarArg...) -> String {
    String(format: texte(cle), locale: .current, arguments: arguments)
}

/// Une chaîne au pluriel, résolue par le `.stringsdict` de la langue.
///
/// Séparée de `texte(_:_:)` pour que le point d'appel dise qu'il y a une règle de pluriel —
/// une clé de `.stringsdict` absente du `.strings` ne se voit pas autrement.
public func texteAuPluriel(_ cle: String, _ nombre: Int) -> String {
    String(format: texte(cle), locale: .current, nombre)
}
