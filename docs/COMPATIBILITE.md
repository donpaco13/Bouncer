# Matrice de compatibilité — Bouncer et les apps d'encoche macOS

> Campagne du 5 septembre 2026.
> Machine de mesure : MacBook Pro (Apple M4, 16 Go), macOS Sequoia. Écran externe LG IPS QHD 2560×1440 en écran principal, écran interne Liquid Retina XDR 1352×878 pt portant l'encoche physique (166×29 pt, zone relevée par Bouncer : `(1212, -29, 166, 29)`).
> Outil de mesure : `Bouncer --self-test` (détection + verdict produit) et une sonde de masquage isolée qui rejoue exactement `ControleurAppsSysteme.masquer` sur un pid donné, sans le filtre de zone d'encoche.

---

## 1. Comment lire cette matrice

Trois étiquettes, jamais mélangées :

- **Mesuré** — l'app a été installée, lancée, et Bouncer a agi dessus sur cette machine. Les chiffres sont ceux du relevé.
- **Prédit** — l'app n'a pas été mesurée, mais son code source montre la propriété qui décide du verdict. La raison est donnée à chaque fois.
- **Inconnu** — ni mesure ni source. La case reste vide plutôt que remplie au jugé.

Une app peut échouer à deux endroits différents, et les deux échecs demandent des correctifs différents :

1. **Bouncer la voit-il ?** Le scan retient une fenêtre collée au bord haut de l'écran, qui couvre la zone de l'encoche, et qui occupe moins de 80 % de la largeur de l'écran. Une app qui dessine son encoche dans un calque plein écran transparent passe à travers ce filet.
2. **Bouncer sait-il l'éteindre ?** Une fois vue, l'app est masquée par `kAXHidden` puis recomptée dans `CGWindowList`. Le masquage marche, ou il ne marche pas.

Les deux questions sont indépendantes. NotchNook se masque en 57 ms et reste pourtant invisible à Bouncer.

---

## 2. La propriété qui décide du verdict

`AXUIElementSetAttributeValue(kAXHiddenAttribute, true)` au niveau application déclenche `-[NSApplication hide:]`. Le WindowServer masque alors les fenêtres de l'app **dans le Space courant**. Une app qui crée son propre Space CGS privé — `CGSSpaceCreate` ou `SLSSpaceCreate`, niveau absolu `2147483647`, maintenu affiché par `CGSShowSpaces` — et qui y insère sa fenêtre d'encoche sort du circuit que `AXHidden` actionne. L'attribut est bien posé, l'API renvoie `0`, et la fenêtre reste à l'écran.

C'est une propriété **observable**, pas une opinion :

- côté source, elle se lit en une ligne : la présence de `CGSSpaceCreate` / `SLSSpaceCreate` appliqué à la fenêtre d'encoche ;
- côté mesure, elle se compte : le nombre de fenêtres à l'écran du pid, avant et après le masquage.

D'où les trois verdicts de Bouncer :

| Verdict | Ce que fait Bouncer | Coût | Condition |
| --- | --- | --- | --- |
| **Voie rapide** | masque et démasque l'app | ~31 ms mesurés en propagation, 46-65 ms de bout en bout | fenêtre d'encoche dans le Space standard |
| **Voie par cycle de vie** | quitte l'app, relance la suivante | ~1 s | fenêtre d'encoche dans un Space CGS privé |
| **Non régissable** | rien | — | Bouncer ne voit jamais la fenêtre, ou la relance ne la ramène pas |

---

## 3. La matrice mesurée

Relevé du 5 septembre 2026. Colonne « fenêtres » : nombre de fenêtres à l'écran du pid avant le masquage → pendant → après. C'est le seul juge du succès ; le code retour de l'API Accessibilité ment sur les apps qui résistent.

### 3.1 Régies aujourd'hui, sans rien changer

| App | Version | bundleID | Fenêtres | Verdict | Détectée par le scan |
| --- | --- | --- | --- | --- | --- |
| **Vibe Island** | 1.0.48 | `app.vibeisland.macos` | 1 → 0 → 1 | **Voie rapide** (46 ms) | oui — bandeau 740 pt (55 %) |
| **Cyclop** | 0.7.0 | `com.cyclop.app` | 2 → 0 → 2 | **Voie rapide** (49 ms) | oui — bandeau 700 pt (52 %) |
| **gh-notch** | 0.4.0 | `company.gh.notch` | 1 → 0 → 1 | **Voie rapide** (47 ms) | oui — bandeau 414 pt (31 %) |
| **boringNotch** | 2.7.3 | `theboringteam.boringnotch` | 1 → 1 → 1 | **Voie par cycle de vie** | oui — bandeau 640 pt (47 %) |

boringNotch est le cas d'école de la voie par cycle de vie, et sa cause est lisible dans son propre dépôt : `NotchSpaceManager` crée un `CGSSpace(level: 2147483647)` au démarrage de l'app, et `createBoringNotchWindow` y insère la fenêtre juste après l'avoir affichée.

### 3.2 Masquables, mais invisibles au scan actuel

Ces trois apps répondent (ou refusent) au masquage de façon parfaitement déterminée. Bouncer ne les voit simplement pas : leur surface d'encoche est un calque qui couvre toute la largeur de l'écran, et le filtre de détection rejette au-delà de 80 %.

| App | Version | bundleID | Largeur de la fenêtre | Fenêtres | Verdict une fois détectée |
| --- | --- | --- | --- | --- | --- |
| **NotchNook** | 1.6.2 | `lo.cafe.NotchNook` | 1352 pt = **100 %** | 3 → 0 → 3 | **Voie rapide** (57 ms) |
| **Notchy** | 1.0.151 | `dev.notchy.app` | 1352 pt = **100 %** | 2 → 2 → 2 | **Voie par cycle de vie** |
| **Mew Notch** | 2.2.2 | `com.monuk7735.mew.notch` | 1352 pt = **100 %** | 2 → 2 → 2 | **Voie par cycle de vie** |

Une seule constante décide : `partEcranMaxFenetreEncoche = 0.8`, dans `ControleurApps.swift`. Le commentaire qui l'accompagne annonçait le cas — « une app d'encoche plus large que 80 % de l'écran serait rejetée à tort ; si le cas se présente, la mesure à relever est sa largeur réelle ». Le cas s'est présenté trois fois, et la mesure est 1352 pt sur un écran de 1352 pt.

Relever le seuil ne suffit pas : à 100 %, le filtre réadmettrait le Dock, la barre de menus du Window Server et les overlays de capture d'écran, qui font eux aussi toute la largeur. Il faut un second discriminant. Ce chantier a son propre coût, et son gain est chiffré : trois apps de plus, dont NotchNook et Notchy.

### 3.3 Mesure non concluante

Ces apps ont été téléchargées, lancées, et n'ont affiché aucune surface d'encoche pendant la campagne — elles attendent qu'un humain passe leur écran d'accueil et leur accorde les autorisations système. Sans fenêtre à l'écran, le recomptage ne mesure rien : `hide` échoue faute d'objet, pas faute de coopération.

| App | Version | bundleID | Ce qu'on a vu | Prédiction par la source |
| --- | --- | --- | --- | --- |
| **Alcove** | 1.7.7 | `com.henrikruscon.Alcove` | fenêtre d'accueil seule, masquée en 57 ms | — (source fermée) |
| **SuperIsland** | 1.0.10 | `com.workview.SuperIsland` | fenêtre d'accueil seule, masquée en 45 ms | voie rapide — aucune API de Space privé dans le dépôt |
| **Atoll** | 2.3.3 | `com.Ebullioscopic.Atoll` | aucune fenêtre | voie rapide — aucune API de Space privé dans le dépôt |
| **DynamicNotch** | 1.6.1 | `com.Jackson.DynamicNotch` | aucune fenêtre | **voie par cycle de vie** — `SkyLightOperator` crée un Space `notchSurface` au niveau `2147483647` et y délègue la fenêtre |
| **Droppy** | 15.0.0-beta.8 | `iordv.Droppy` | aucune fenêtre | — (source fermée) |
| **MediaMate** | 3.8.4 | `com.tweety.MediaMate` | masquée en 65 ms, mais sa fenêtre 164×29 était garée hors de l'écran porteur | — (source fermée) |

Que le masquage marche sur une fenêtre d'accueil ne dit rien de la surface d'encoche : c'est la fenêtre d'encoche qui peut vivre dans un Space privé, pas la fenêtre de réglages. Ces six lignes sont donc des mesures partielles, et elles sont présentées comme telles.

---

## 4. La matrice prédite — lecture de source

Pour chaque dépôt ouvert : clone superficiel, recherche de `CGSSpaceCreate`, `SLSSpaceCreate`, `CGSShowSpaces`, `CGSAddWindowsToSpaces`, `SkyLight`, puis lecture du site d'appel pour vérifier que le Space concerne bien la fenêtre d'encoche.

**Voie par cycle de vie prédite** — la signature est là, appliquée à la surface d'encoche :

| Dépôt | App | Où la signature se lit |
| --- | --- | --- |
| `jackson-storm/DynamicNotch` | DynamicNotch | `SkyLightOperator.swift` : `notchSurface = 2_147_483_647`, `delegateWindow(window, to: .notchSurface)` |
| `monuk7735/mew-notch` | Mew Notch | `NotchSpaceManager.swift` : `CGSSpace(level: 2147483647)` — mesure concordante |
| `AppGram/agentnotch` | AgentNotch | `Window/CGSSpace.swift` |
| `talkvalue/Buddi` | Buddi | `private/CGSSpace.swift` + `BuddiSkyLightWindow.swift` — dérivé direct de boringNotch |
| `TheBoredTeam/boring.notch` | boringNotch | `NotchSpaceManager.swift` — mesure concordante |

**Voie rapide prédite** — aucune création de Space privé dans le dépôt :

`shobhit99/SuperIsland`, `Lakr233/NotchDrop`, `dV27-2007/dynamic-island-macos`, `akalikbergenov/cyclop` (mesure concordante), `aymandakirgh/ghnotch` (mesure concordante), `BadRat-in/MacIsland`, `wxtsky/CodeIsland`, `MioMioOS/MioIsland`, `ericjypark/codex-island`, `Ebullioscopic/Atoll`.

**`Notchly/Notchly`** appelle bien SkyLight, mais uniquement `SLSCopyManagedDisplaySpaces`, en lecture, pour savoir si le Space courant est en plein écran. Il ne crée aucun Space, et son verdict prédit est donc la voie rapide. Chercher le mot « SkyLight » sans lire le site d'appel aurait donné la réponse inverse.

**Cas particulier — `mrkai77/DynamicNotchKit`.** Ce n'est pas une app mais une bibliothèque, utilisée par plusieurs des projets ci-dessus. Elle n'ouvre aucun Space privé : les apps qui l'emploient héritent de la voie rapide, sauf à ajouter elles-mêmes le Space, ce que fait Buddi.

---

## 5. Le recensement du marché

Applications macOS qui occupent l'encoche, au 5 septembre 2026. Les bundleIDs marqués **✓** ont été relevés dans le `Info.plist` de l'app téléchargée sur la machine de mesure — ce ne sont pas des suppositions.

### 5.1 Commerciales

| App | Éditeur | Prix | bundleID | Site |
| --- | --- | --- | --- | --- |
| NotchNook | lo.cafe | 25 $ à vie ou 3 $/mois | `lo.cafe.NotchNook` ✓ | lo.cafe/notchnook |
| Alcove | Henrik Rusconi | 14,99 $ | `com.henrikruscon.Alcove` ✓ | tryalcove.com |
| Droppy | Jordy Spruit | 8,55 € à vie | `iordv.Droppy` ✓ | getdroppy.app |
| MediaMate | Wouter Hennen | gratuit, soutien 4,99 $ | `com.tweety.MediaMate` ✓ | wouter01.github.io/MediaMate |
| DynamicLake Pro | Liqoria (Aviorrok) | 13,99 $ | inconnu | dynamiclake.com |
| Seam | inconnu | 19,90 $ | inconnu | getseam.app |
| MacNotch | MacNotch | 22,99 $ ou 3,99 $/mois | inconnu | macnotch.io |
| Moody | mjarosz | 59 $ | inconnu | moody.mjarosz.com |

### 5.2 Gratuites et open source

| App | Éditeur / dépôt | Licence | bundleID | Site |
| --- | --- | --- | --- | --- |
| Notchy | Vishva Variya | gratuit, source fermée | `dev.notchy.app` ✓ | notchy.dev |
| Vibe Island | — | gratuit, source fermée | `app.vibeisland.macos` ✓ | — |
| boringNotch | TheBoredTeam/boring.notch | GPL-3.0 | `theboringteam.boringnotch` ✓ | github.com/TheBoredTeam/boring.notch |
| Atoll | Ebullioscopic/Atoll | GPL-3.0 | `com.Ebullioscopic.Atoll` ✓ | getatoll.app |
| Mew Notch | monuk7735/mew-notch | ouverte | `com.monuk7735.mew.notch` ✓ | github.com/monuk7735/mew-notch |
| DynamicNotch | jackson-storm/DynamicNotch | ouverte | `com.Jackson.DynamicNotch` ✓ | github.com/jackson-storm/DynamicNotch |
| SuperIsland | shobhit99/SuperIsland | ouverte | `com.workview.SuperIsland` ✓ | github.com/shobhit99/SuperIsland |
| Cyclop | akalikbergenov/cyclop | ouverte | `com.cyclop.app` ✓ | github.com/akalikbergenov/cyclop |
| gh-notch | aymandakirgh/ghnotch | ouverte | `company.gh.notch` ✓ | github.com/aymandakirgh/ghnotch |
| NotchDrop | Lakr233/NotchDrop | ouverte | inconnu | github.com/Lakr233/NotchDrop |
| MacIsland | BadRat-in/MacIsland | ouverte | inconnu | github.com/BadRat-in/MacIsland |

### 5.3 La vague des agents de code

Une famille entière est apparue en 2026 : des apps d'encoche qui affichent l'état d'un agent de code. Elles occupent l'encoche au même titre que les autres et relèvent de la même matrice.

| App | Dépôt | Ce qu'elle montre |
| --- | --- | --- |
| CodeIsland | wxtsky/CodeIsland | état d'un agent, avec relais iPhone et Apple Watch |
| MioIsland | MioMioOS/MioIsland | sessions Claude Code |
| codex-island | ericjypark/codex-island | quotas d'usage |
| AgentNotch | AppGram/agentnotch | assistants de code en temps réel |
| Buddi | talkvalue/Buddi | compagnon Claude Code |
| Notchly | Notchly/Notchly | notifications d'agents |

### 5.4 Hors périmètre

- **OnlySwitch** (`jacklandrin/OnlySwitch`, 5,9 k étoiles) *masque* l'encoche au lieu de l'occuper. Rien à arbitrer.
- **DynamicNotchKit** (`mrkai77/DynamicNotchKit`) est une bibliothèque.
- **FlippingNotch**, **NotchPrompter**, **NotchyAlert** utilisent le mot « notch » pour autre chose.

---

## 6. Ce que cette campagne n'a pas pu établir

1. **Six apps n'ont pas affiché leur surface d'encoche.** Elles attendent un passage par leur écran d'accueil et l'octroi d'autorisations système, qui demandent une main humaine devant l'écran. Leur verdict reste prédit, jamais mesuré.
2. **Quatre apps commerciales n'ont pas été téléchargées** — DynamicLake Pro, Seam, MacNotch, Moody. Ni bundleID, ni verdict.
3. **Une seule configuration matérielle a servi de banc.** Écran interne à encoche en position secondaire, écran externe principal. Une app qui se comporte autrement quand l'écran à encoche est l'écran principal n'aurait pas été vue ici.

---

## 7. Ce qui change pour le produit

Par ordre d'effet :

1. **Le filtre de détection à 80 % coûte trois apps majeures**, dont NotchNook et Notchy. La cause est mesurée au point près ; le correctif demande un second discriminant contre les overlays plein écran du système, pas seulement un seuil relevé.
2. **Onze bundleIDs sont désormais relevés à la source**, contre deux dans l'amorçage du catalogue. Chaque ajout dispense l'utilisateur d'attendre que l'apprentissage rattrape son app.
3. **`--self-test` rend maintenant un verdict.** Il imprimait « Test en cours… » et sortait avant que le test de support ne se termine. Il pompe désormais la boucle principale jusqu'à ce que toutes les apps aient leur verdict, plafonné à 15 s. C'est ce changement qui a rendu la campagne possible.
