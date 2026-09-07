//
// CatalogueDeChainesTests.swift — le catalogue de chaînes tient ou il ne tient pas.
//
// Une chaîne localisée qui retombe sur sa clé ne casse rien : l'app démarre, l'interface
// affiche « menu.settings », et personne ne le voit avant un utilisateur. Ces tests-là
// existent pour que ça se voie au build.
//
// Ils lisent les `.strings` du BUNDLE CONSTRUIT, pas les fichiers source : c'est le seul moyen
// de prouver que SwiftPM les a bien compilés et posés là où `Bundle.module` les cherchera.
//
// La liste des langues n'est pas écrite ici : c'est `LangueInterface` qui la porte, et c'est
// exprès — une langue ajoutée au sélecteur sans son `.lproj` échoue ici, et l'inverse aussi.
//

import Foundation
import Testing
@testable import BouncerCore

struct CatalogueDeChainesTests {

    /// Les codes `.lproj` de toutes les langues que le sélecteur propose. L'anglais est la
    /// source ; les autres doivent lui être strictement parallèles.
    private static let langues: [String] = LangueInterface.allCases.compactMap(\.code)
    private static let traductions: [String] = langues.filter { $0 != "en" }

    private static func lproj(_ langue: String) throws -> Bundle {
        try #require(
            catalogueDeChaines.path(forResource: langue, ofType: "lproj").flatMap(Bundle.init(path:)),
            "\(langue).lproj absent du bundle construit"
        )
    }

    private static func table(_ langue: String) throws -> [String: String] {
        let chemin = try #require(
            try lproj(langue).path(forResource: "Localizable", ofType: "strings"),
            "Localizable.strings absent de \(langue).lproj"
        )
        return try #require(
            NSDictionary(contentsOfFile: chemin) as? [String: String],
            "Localizable.strings de \(langue) illisible"
        )
    }

    private static func pluriels(_ langue: String) throws -> [String: Any] {
        let chemin = try #require(
            try lproj(langue).path(forResource: "Localizable", ofType: "stringsdict"),
            "Localizable.stringsdict absent de \(langue).lproj"
        )
        return try #require(NSDictionary(contentsOfFile: chemin) as? [String: Any])
    }

    /// Les trous de format d'une chaîne, triés : `%@`, `%d`, `%1$@`, `%2$d`… Un `%%` littéral
    /// n'en est pas un.
    private static func trous(_ valeur: String) -> [String] {
        let motif = try! NSRegularExpression(pattern: "%(?:%|(?:\\d+\\$)?[@dfs])")
        let plage = NSRange(valeur.startIndex..., in: valeur)
        return motif.matches(in: valeur, range: plage).compactMap {
            Range($0.range, in: valeur).map { String(valeur[$0]) }
        }.filter { $0 != "%%" }.sorted()
    }

    /// Sans ça, `swift build` a recopié les `.lproj` sans les reconnaître comme des langues, et
    /// TOUTES les chaînes retomberaient sur leur clé sans un mot d'avertissement. C'est le
    /// défaut qu'un String Catalog `.xcstrings` produit ici — mesuré, cf. Localisation.swift.
    /// Et c'est aussi ce qui attrape une langue du sélecteur sans dossier, ou l'inverse.
    @Test func leBundlePorteToutesLesLangues() {
        #expect(Set(catalogueDeChaines.localizations) == Set(Self.langues))
    }

    /// La parité stricte des clés avec l'anglais. Une clé ajoutée en anglais et oubliée dans une
    /// langue s'y afficherait en anglais ; une clé en trop n'est pas une traduction, c'est une
    /// faute de frappe.
    @Test(arguments: traductions)
    func chaqueLanguePorteLesMemesClesQueLAnglais(langue: String) throws {
        let en = Set(try Self.table("en").keys)
        let autre = Set(try Self.table(langue).keys)
        #expect(en.subtracting(autre).isEmpty, "clés sans traduction \(langue) : \(en.subtracting(autre).sorted())")
        #expect(autre.subtracting(en).isEmpty, "clés \(langue) sans source anglaise : \(autre.subtracting(en).sorted())")
    }

    @Test(arguments: traductions)
    func chaqueLanguePorteLesMemesPluriels(langue: String) throws {
        let en = Set(try Self.pluriels("en").keys)
        let autre = Set(try Self.pluriels(langue).keys)
        #expect(en == autre, "pluriels dépareillés en \(langue) : \(en.symmetricDifference(autre).sorted())")
    }

    /// Aucune valeur vide, dans aucune langue : une chaîne vide passe la parité des clés et
    /// s'affiche comme un trou dans l'interface.
    @Test(arguments: langues)
    func aucuneValeurVide(langue: String) throws {
        let vides = try Self.table(langue).filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(vides.isEmpty, "valeurs vides en \(langue) : \(vides.keys.sorted())")
    }

    /// Les trous d'une chaîne à format doivent se correspondre d'une langue à l'autre : une
    /// traduction qui perd un `%@` ou en ajoute un fait planter `String(format:)` à l'exécution.
    @Test(arguments: traductions)
    func lesTrousDeFormatSeCorrespondent(langue: String) throws {
        let en = try Self.table("en")
        let autre = try Self.table(langue)
        for (cle, valeurEn) in en {
            guard let valeurAutre = autre[cle] else { continue }  // couvert par la parité des clés
            #expect(
                Self.trous(valeurEn) == Self.trous(valeurAutre),
                "\(cle) : trous \(Self.trous(valeurEn)) en anglais, \(Self.trous(valeurAutre)) en \(langue)"
            )
        }
    }

    /// Un `%` nu dans une traduction — « 3 % » écrit sans le doubler — est un spécificateur de
    /// format incomplet : `String(format:)` l'interprète, et la phrase sort tronquée ou plante.
    @Test(arguments: langues)
    func aucunPourcentNu(langue: String) throws {
        let motif = try NSRegularExpression(pattern: "(?<!%)%(?!%|(?:\\d+\\$)?[@dfs])")
        for (cle, valeur) in try Self.table(langue) {
            let plage = NSRange(valeur.startIndex..., in: valeur)
            #expect(motif.firstMatch(in: valeur, range: plage) == nil, "\(cle) en \(langue) : « % » nu")
        }
    }

    /// La preuve de bout en bout : la fonction que le reste du code appelle rend bien la phrase
    /// et non la clé, dans chaque langue du sélecteur.
    @Test(arguments: LangueInterface.allCases.filter { $0 != .systeme })
    func texteNeRendJamaisLaCle(langue: LangueInterface) throws {
        activerLangue(langue)
        defer { activerLangue(.en) }
        for cle in try Self.table("en").keys {
            #expect(texte(cle) != cle, "\(cle) retombe sur sa clé en \(langue.rawValue)")
        }
    }

    /// Le changement de langue s'applique sans relance, et se défait de même.
    @Test func changerDeLangueChangeLesChainesToutDeSuite() throws {
        defer { activerLangue(.en) }
        activerLangue(.en)
        let anglais = texte("menu.settings")
        activerLangue(.fr)
        let frTable = try Self.table("fr")
        #expect(texte("menu.settings") == frTable["menu.settings"])
        #expect(texte("menu.settings") != anglais)
        activerLangue(.en)
        #expect(texte("menu.settings") == anglais)
    }

    /// Le pluriel passe par le `.stringsdict`, pas par le `.strings` : si le fichier n'était pas
    /// posé dans le bundle, `texteAuPluriel` rendrait la clé sans broncher. Et il suit la langue
    /// CHOISIE, pas celle de la machine : en anglais, zéro est un pluriel.
    @Test func lePlurielEstResolu() {
        defer { activerLangue(.en) }
        activerLangue(.en)
        let zero = texteAuPluriel("welcome.ready.appsFound", 0)
        let une = texteAuPluriel("welcome.ready.appsFound", 1)
        let trois = texteAuPluriel("welcome.ready.appsFound", 3)
        #expect(une != "welcome.ready.appsFound")
        #expect(une != trois, "le singulier et le pluriel rendent la même phrase")
        #expect(trois.contains("3"))
        #expect(zero.contains("0"), "zéro app rend « \(zero) » : la règle de pluriel n'est pas celle de l'anglais")
    }

    /// Chaque langue résout ses deux pluriels sans retomber sur la clé — le `.stringsdict` d'une
    /// langue à une seule forme (`other`) doit marcher comme celui d'une langue à deux.
    @Test(arguments: LangueInterface.allCases.filter { $0 != .systeme })
    func lesPlurielsDeChaqueLangueSontResolus(langue: LangueInterface) {
        activerLangue(langue)
        defer { activerLangue(.en) }
        for cle in ["welcome.ready.appsFound", "settings.general.refresh.interval"] {
            for n in [0, 1, 2, 5] {
                let rendu = texteAuPluriel(cle, n)
                #expect(rendu != cle, "\(cle) retombe sur sa clé en \(langue.rawValue)")
                #expect(!rendu.contains("%"), "\(cle) en \(langue.rawValue) pour \(n) : « \(rendu) » garde un trou")
            }
        }
    }
}
