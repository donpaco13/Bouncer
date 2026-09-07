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

import Foundation
import Testing
@testable import BouncerCore

struct CatalogueDeChainesTests {

    /// Les langues déclarées, telles que le bundle construit les porte.
    private static let langues = ["en", "fr"]

    private static func table(_ langue: String) throws -> [String: String] {
        let bundle = try #require(
            catalogueDeChaines.path(forResource: langue, ofType: "lproj").flatMap(Bundle.init(path:)),
            "\(langue).lproj absent du bundle construit"
        )
        let chemin = try #require(
            bundle.path(forResource: "Localizable", ofType: "strings"),
            "Localizable.strings absent de \(langue).lproj"
        )
        return try #require(
            NSDictionary(contentsOfFile: chemin) as? [String: String],
            "Localizable.strings de \(langue) illisible"
        )
    }

    private static func pluriels(_ langue: String) throws -> [String: Any] {
        let bundle = try #require(
            catalogueDeChaines.path(forResource: langue, ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let chemin = try #require(
            bundle.path(forResource: "Localizable", ofType: "stringsdict"),
            "Localizable.stringsdict absent de \(langue).lproj"
        )
        return try #require(NSDictionary(contentsOfFile: chemin) as? [String: Any])
    }

    /// Sans ça, `swift build` a recopié les `.lproj` sans les reconnaître comme des langues, et
    /// TOUTES les chaînes retomberaient sur leur clé sans un mot d'avertissement. C'est le
    /// défaut qu'un String Catalog `.xcstrings` produit ici — mesuré, cf. Localisation.swift.
    @Test func leBundlePorteLesDeuxLangues() {
        #expect(Set(catalogueDeChaines.localizations) == Set(Self.langues))
    }

    /// La parité stricte des clés. Une clé ajoutée en anglais et oubliée en français
    /// s'afficherait en anglais chez un utilisateur français ; l'inverse afficherait la clé.
    @Test func lesDeuxLanguesPortentLesMemesCles() throws {
        let en = Set(try Self.table("en").keys)
        let fr = Set(try Self.table("fr").keys)
        #expect(en.subtracting(fr).isEmpty, "clés sans traduction française : \(en.subtracting(fr).sorted())")
        #expect(fr.subtracting(en).isEmpty, "clés françaises sans source anglaise : \(fr.subtracting(en).sorted())")
    }

    @Test func lesDeuxLanguesPortentLesMemesPluriels() throws {
        let en = Set(try Self.pluriels("en").keys)
        let fr = Set(try Self.pluriels("fr").keys)
        #expect(en == fr, "pluriels dépareillés : \(en.symmetricDifference(fr).sorted())")
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
    @Test func lesTrousDeFormatSeCorrespondent() throws {
        let en = try Self.table("en")
        let fr = try Self.table("fr")
        let motif = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfs]")

        func trous(_ valeur: String) -> [String] {
            let plage = NSRange(valeur.startIndex..., in: valeur)
            return motif.matches(in: valeur, range: plage).compactMap {
                Range($0.range, in: valeur).map { String(valeur[$0]) }
            }.sorted()
        }

        for (cle, valeurEn) in en {
            guard let valeurFr = fr[cle] else { continue }  // couvert par la parité des clés
            #expect(
                trous(valeurEn) == trous(valeurFr),
                "\(cle) : trous \(trous(valeurEn)) en anglais, \(trous(valeurFr)) en français"
            )
        }
    }

    /// La preuve de bout en bout : la fonction que le reste du code appelle rend bien la phrase
    /// et non la clé. `texte` lit la langue de l'utilisateur ; on vérifie donc juste qu'elle ne
    /// retombe pas sur la clé, quelle que soit la langue de la machine qui lance les tests.
    @Test func texteNeRendJamaisLaCle() throws {
        for cle in try Self.table("en").keys {
            #expect(texte(cle) != cle, "\(cle) retombe sur sa clé")
        }
    }

    /// Le pluriel passe par le `.stringsdict`, pas par le `.strings` : si le fichier n'était pas
    /// posé dans le bundle, `texteAuPluriel` rendrait la clé sans broncher.
    @Test func lePlurielEstResolu() {
        let une = texteAuPluriel("welcome.ready.appsFound", 1)
        let trois = texteAuPluriel("welcome.ready.appsFound", 3)
        #expect(une != "welcome.ready.appsFound")
        #expect(une != trois, "le singulier et le pluriel rendent la même phrase")
        #expect(trois.contains("3"))
    }
}
