# Bascule par cycle de vie — plan d'implémentation

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Bouncer fait basculer le notch d'une app à l'autre même quand l'app résiste au masquage, en la quittant et en lançant la suivante.

**Architecture:** Deux méthodes choisies par app selon son verdict de régissabilité — masquage Accessibilité pour celles qui répondent, cycle de vie du process pour celles qui épinglent leurs fenêtres dans un Space privé. Le modèle passe d'une clé `pid` à une clé `bundleID`, parce qu'une app tuée n'a plus de pid. Les actions sur les apps tierces passent derrière un protocole, seul moyen de tester la machine à états sans tuer de vraies apps.

**Tech Stack:** Swift 5.9, AppKit, `NSWorkspace`, `NSRunningApplication`, `CGWindowListCopyWindowInfo`, `kAXHiddenAttribute`, swift-testing ou XCTest via SwiftPM.

---

## Contexte que l'implémenteur n'a pas

Lire `docs/plans/2026-09-01-bouncer-bascule-design.md` avant de commencer. Le résumé utile :

Quatre apps de notch existent (Vibe Island, boringNotch, Alcove, Notchy). Une seule, Vibe Island,
se laisse masquer par `kAXHiddenAttribute`. Les trois autres créent un Space privé auprès du
WindowServer et y épinglent leurs fenêtres : l'ordre de masquage est accepté, ne renvoie aucune
erreur, et ne change rien à l'écran. **Le seul juge de vérité d'un masquage est le recomptage
`CGWindowList` sur le pid ciblé** — ni le code retour de l'API Accessibility ni la relecture de
l'attribut ne signalent l'échec.

Deux pièges du projet, déjà payés cher :

1. **Ne JAMAIS appeler l'API AX si `AXIsProcessTrusted()` est faux.** Un appel émis avant l'octroi
   du trust laisse la connexion Accessibility du process hors service pour le reste de sa vie,
   même après que l'utilisateur accorde la permission. La garde existe dans `refresh()`, ne la
   retire pas.
2. **`testSupport(pid:)` est destructif** : il masque puis réaffiche réellement la fenêtre pour
   déterminer la régissabilité. Un cache par pid existe pour ne pas le rejouer. Ne le contourne pas.

`./build.sh` ne peut pas tourner dans un sandbox d'agent (codesign + trousseau). Utilise
`swift build` ; l'orchestrateur produit le bundle signé et relance l'app.

---

### Task 0 : Cible de test

**Files:**
- Modify: `Package.swift`
- Create: `Tests/BouncerTests/CycleTests.swift`

Le projet n'a aucun test aujourd'hui. Tout le reste du plan en dépend.

**Step 1: Ajouter la cible de test à Package.swift**

La target exécutable ne peut pas être importée par une target de test. Extraire la logique dans
une target bibliothèque `BouncerCore`, et laisser `Bouncer` comme mince exécutable qui en dépend.

```swift
products: [
    .executable(name: "Bouncer", targets: ["Bouncer"])
],
targets: [
    .target(name: "BouncerCore", path: "Sources/BouncerCore"),
    .executableTarget(name: "Bouncer", dependencies: ["BouncerCore"], path: "Sources/Bouncer"),
    .testTarget(name: "BouncerTests", dependencies: ["BouncerCore"], path: "Tests/BouncerTests"),
]
```

Déplacer `WindowManager.swift` dans `Sources/BouncerCore/`, marquer `public` ce que l'exécutable
utilise. `main.swift`, `App.swift`, `MenuBarContentView.swift`, `NotchOverlay.swift` restent dans
`Sources/Bouncer/`.

**Step 2: Écrire un test qui échoue**

```swift
import XCTest
@testable import BouncerCore

final class CycleTests: XCTestCase {
    func testCibleSuivanteEnAvant() {
        let apps = ["a", "b", "c"]
        XCTAssertEqual(prochaineCible(dans: apps, depuis: "a", forward: true), "b")
    }
}
```

**Step 3: Vérifier qu'il échoue**

Run: `swift test`
Expected: erreur de compilation, `prochaineCible` n'existe pas.

**Step 4: Implémentation minimale dans `Sources/BouncerCore/Cycle.swift`**

```swift
func prochaineCible<T: Equatable>(dans liste: [T], depuis courant: T?, forward: Bool) -> T? {
    guard !liste.isEmpty else { return nil }
    guard let courant, let idx = liste.firstIndex(of: courant) else { return liste.first }
    let n = liste.count
    return liste[forward ? (idx + 1) % n : (idx - 1 + n) % n]
}
```

**Step 5: Vérifier que le test passe, puis commit**

```bash
swift test
git add Package.swift Sources Tests
git commit -m "Cible de test et calcul du prochain élément du cycle"
```

---

### Task 1 : Le modèle passe d'une clé pid à une clé bundleID

**Files:**
- Modify: `Sources/BouncerCore/WindowManager.swift` (`NotchAppInfo`, `refresh`, `updateApp`, `toggle`, `cycle`)
- Test: `Tests/BouncerTests/ModeleTests.swift`

**Pourquoi:** `NotchAppInfo.id` vaut `pid` aujourd'hui. Une app tuée n'a plus de pid mais doit
rester dans la liste — c'est elle qu'on relancera. L'identité stable d'une app est son bundleID.

**Step 1: Écrire le test qui échoue**

```swift
func testAppTueeResteDansLaListeSansPid() {
    var app = NotchAppInfo(bundleID: "com.example.notch", name: "Exemple",
                           support: .supported, pid: 1234, isHiddenByUs: false)
    app.pid = nil
    XCTAssertEqual(app.id, "com.example.notch")
    XCTAssertFalse(app.estLancee)
}
```

**Step 2:** `swift test` → échoue, `pid` n'est pas optionnel et `id` n'est pas un `String`.

**Step 3: Modifier le modèle**

```swift
public struct NotchAppInfo: Identifiable, Equatable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public var support: SupportStatus
    /// nil quand l'app n'est pas lancée. Une app tuée reste listée : c'est elle qu'on relancera.
    public var pid: pid_t?
    public var isHiddenByUs: Bool
    public var estLancee: Bool { pid != nil }
}
```

Répercuter dans `updateApp`, `toggle`, `cycle`, `testSupport`, le cache de verdict et
`MenuBarContentView`. Le cache de verdict passe lui aussi de `[pid_t: SupportStatus]` à
`[String: SupportStatus]`, ce qui règle au passage le risque de recyclage de pid.

Un process sans bundleID (rare, ex. Window Server) est écarté à la découverte : sans identité
stable, on ne peut ni le relancer ni mémoriser son verdict.

**Step 4:** `swift test` → passe. **Step 5:** commit `Identité des apps par bundleID, le pid devient optionnel`.

---

### Task 2 : Catalogue des apps de notch installées

**Files:**
- Create: `Sources/BouncerCore/CatalogueApps.swift`
- Test: `Tests/BouncerTests/CatalogueTests.swift`

**Pourquoi:** la liste ne peut plus se construire uniquement sur `CGWindowList` : une app tuée en
disparaît. Il faut connaître les apps de notch **installées**, lancées ou non.

**Le mécanisme:** Bouncer apprend. Toute app découverte une fois dans le notch voit son bundleID
mémorisé dans `UserDefaults`. Le catalogue = (bundleIDs appris ∪ liste d'amorçage) ∩ apps
réellement présentes sur le disque, résolues par `NSWorkspace.urlForApplication(withBundleIdentifier:)`.

La liste d'amorçage sert au premier lancement, avant tout apprentissage :

```swift
let amorcage: Set<String> = [
    "app.vibeisland.macos",       // Vibe Island
    "com.thecoolbeans.boringnotch", // boringNotch — VÉRIFIER le bundleID réel
    "com.tryalcove.alcove",       // Alcove — VÉRIFIER
    "dev.notchy.notchy",          // Notchy — VÉRIFIER
]
```

**Vérifie chaque bundleID d'amorçage** avec
`mdls -name kMDItemCFBundleIdentifier /Applications/<App>.app` sur les quatre apps, qui sont
installées sur cette machine. Ne recopie pas ceux ci-dessus, ils sont approximatifs.

**Step 1: Test qui échoue** — un catalogue construit à partir d'un résolveur injecté renvoie
uniquement les apps que le résolveur dit installées. Injecter le résolveur (`(String) -> URL?`)
plutôt que d'appeler `NSWorkspace` directement, sinon le test dépend de la machine.

**Steps 2-5:** implémenter, tester, commiter `Catalogue des apps de notch installées, appris et persisté`.

---

### Task 3 : Les actions sur les apps tierces passent derrière un protocole

**Files:**
- Create: `Sources/BouncerCore/ControleurApps.swift`
- Test: `Tests/BouncerTests/BasculeTests.swift`

**Pourquoi:** la machine à états de la bascule ne peut pas être testée si elle tue de vraies apps.
C'est la seule raison d'être de ce protocole — il a deux implémentations, la vraie et le double de
test, il n'est donc pas une abstraction gratuite.

```swift
public protocol ControleurApps {
    func lancer(bundleID: String) async -> Bool
    func tuer(pid: pid_t) -> Bool
    func masquer(_ masquee: Bool, pid: pid_t) -> Bool
    /// Vraie mesure : recomptage CGWindowList sur les fenêtres du pid dans la zone du notch.
    func fenetreVisibleDansNotch(pid: pid_t) -> Bool
    func pid(pour bundleID: String) -> pid_t?
}
```

L'implémentation réelle (`ControleurAppsSysteme`) reprend le code existant : `setHidden` pour
`masquer`, le recomptage `CGWindowList` pour `fenetreVisibleDansNotch`,
`NSWorkspace.openApplication` pour `lancer`, `NSRunningApplication.terminate()` pour `tuer`.

Commit : `Protocole des actions sur les apps tierces, et son implémentation système`.

---

### Task 4 : La machine à états de la bascule

**Files:**
- Create: `Sources/BouncerCore/Bascule.swift`
- Test: `Tests/BouncerTests/BasculeTests.swift`

**La séquence, validée avec le propriétaire** — on lance la suivante AVANT de tuer la précédente,
pour que l'utilisateur ne voie jamais un notch vide :

1. si la cible est régissable et déjà lancée → `masquer(false)` sur elle, `masquer(true)` sur
   l'actuelle. Fin. C'est la voie rapide, 31 ms, l'app reste chaude.
2. sinon → `lancer(cible)`, puis sonder `fenetreVisibleDansNotch(cible)` toutes les 50 ms
3. dès que la fenêtre de la cible apparaît → `tuer(actuelle)` si l'actuelle est résistante,
   `masquer(true)` si elle est régissable
4. **timeout à 5 s.** Si la fenêtre de la cible n'apparaît jamais, **ne pas toucher à l'actuelle**
   et remonter l'échec. L'utilisateur garde l'app qu'il avait.

**Les tests à écrire, avec le double du protocole** — ce sont eux qui donnent sa valeur à la task :

- la cible apparaît au bout de 3 sondages → l'actuelle est tuée, et pas avant
- la cible n'apparaît jamais → `tuer` n'est JAMAIS appelé, la bascule renvoie un échec
- la cible est régissable et lancée → `lancer` n'est jamais appelé, seulement deux `masquer`
- l'actuelle est régissable → elle est masquée, pas tuée
- une seule app dans le catalogue → bascule visible/masquée sur elle-même, comportement actuel préservé

Commit : `Bascule par cycle de vie, avec pré-lancement et timeout`.

---

### Task 5 : Brancher la bascule sur le swipe, les flèches et le menu

**Files:**
- Modify: `Sources/BouncerCore/WindowManager.swift` (`cycle`, `toggle`)
- Modify: `Sources/Bouncer/MenuBarContentView.swift`

`cycle(forward:)` délègue à la machine à états. `cyclableApps` ne filtre plus sur
`support == .supported` — une app résistante participe désormais au cycle, c'est tout l'objet du
changement.

**Le menu change de nature.** Aujourd'hui il affiche « Vibe Island — Régissable » : c'est le
verdict d'un test interne, du vocabulaire de développeur, et ça ne dit pas à l'utilisateur ce qui
l'intéresse. Demandé par le propriétaire, et c'est la bonne lecture du produit :

- **Cliquer sur une app la rend active.** Elle s'ouvre si elle est arrêtée, et l'app qui occupait
  le notch est masquée ou quittée selon sa méthode. C'est exactement l'action du swipe, déclenchée
  depuis le menu. `toggle(pid:)` disparaît au profit d'un `rendreActive(bundleID:)` qui appelle la
  même machine à états que le swipe — une seule voie de code, pas deux comportements à maintenir.
- **Le libellé dit l'état, pas le verdict.** Le nom de l'app, et une marque sur celle qui occupe le
  notch. Rien d'autre par défaut.
- **Le verdict ne disparaît pas, il change de place.** Il reste utile : il explique pourquoi une
  bascule est instantanée et l'autre prend une seconde. Il devient une information secondaire —
  un sous-titre discret, une infobulle — et surtout il cesse d'être une raison de griser l'entrée.
  Une app résistante est cliquable comme les autres, c'est le point de tout ce chantier.
- **Une app en cours de bascule doit se voir.** La voie cycle de vie prend ~1 s : sans retour
  visuel, l'utilisateur clique deux fois. Un état « en cours » sur l'entrée concernée.

L'échec de bascule doit être visible, pas avalé en silence : si la cible n'apparaît jamais, l'app
courante reste active et l'erreur s'affiche.

Commit : `Le swipe, les flèches et le menu passent par la même bascule`.

---

### Task 6 : Validation en réel — par le propriétaire, pas par un agent

Aucun agent ne peut valider ça : le geste physique et le rendu du notch ne sont pas observables
sans écran.

L'orchestrateur lance `./build.sh` (qui relance l'app), puis le propriétaire vérifie :

- [ ] boringNotch et Vibe Island toutes deux installées, une seule visible dans le notch
- [ ] swipe → l'autre apparaît, la première disparaît, jamais de notch vide entre les deux
- [ ] la bascule vers Vibe Island est instantanée (voie AX), celle vers boringNotch prend ~1 s (voie cycle de vie)
- [ ] quitter Bouncer ne laisse aucune app masquée ni aucune app tuée sans remplaçante
- [ ] mesurer le temps réel de la voie cycle de vie et le noter — « ultra rapide » est un objectif du propriétaire, il faut un chiffre pour savoir si on y est
