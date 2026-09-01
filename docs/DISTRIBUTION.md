# Distribution de Bouncer par Homebrew

Vérifié le 2026-09-01 contre Homebrew 6.0.20 installé en local
(`/opt/homebrew`, source Ruby + historique git), et par test Gatekeeper
sur cette machine.

## Le point le plus important : Homebrew ne retire plus la quarantaine

**C'est faux, et le contournement documenté n'existe plus non plus.**

Homebrew Cask met les téléchargements en quarantaine, et depuis la 4.7.0 il
n'y a plus aucun moyen de le désactiver côté utilisateur.

Ce que dit le code de la 6.0.20 :

- `cask/download.rb:75` et `:210` appellent `quarantine(path)` sur le fichier
  téléchargé. La seule condition est `Quarantine.available?`
  (`cask/download.rb:253`), qui vaut vrai sur macOS dès que `xattr` répond
  (`extend/os/mac/cask/quarantine.rb`, `check_quarantine_support`).
  Aucun test sur le tap, le cask ou l'utilisateur.
- L'attribut est posé avec `LSQuarantineTypeWebDownload` via LaunchServices,
  agent « Homebrew Cask » (même fichier, `cask!`).
- `cask/artifact/moved.rb:160` recopie les xattrs sur la cible au moment du
  déplacement. L'app dans `/Applications` est donc bien en quarantaine, pas
  seulement le `.dmg`.

Et le flag est mort :

```
$ brew install --cask --no-quarantine firefox
Error: invalid option: --no-quarantine
```

Trois commits dans `Homebrew/brew` racontent la fin :

| Commit | Date | Objet |
|---|---|---|
| `a84673836c` | 2025-09-29 | durcit le message d'avertissement de `--no-quarantine` |
| `ffe954753b` | 2025-10-23 | le cache de la doc et des complétions, « we're going to deprecate this in 4.7.0 » |
| `ba25213c81` | 2026-07-30 | supprime le code résiduel |

La position du projet est écrite dans sa doc
(`docs/Homebrew-Security-and-Supply-Chain.md:207`) : « Homebrew applies macOS
quarantine attributes to Cask downloads so Gatekeeper performs these checks
instead of Homebrew bypassing them. »

**Aucune strophe du DSL ne change ça.** `cask/dsl.rb` ne contient pas une seule
occurrence de « quarantine ». `auto_updates` ne concerne que le comportement de
`brew upgrade`, `depends_on` que les prérequis. Il n'y a pas d'équivalent cask
d'un opt-out.

Conséquence directe : `brew install --cask bouncer` sur une app signée avec un
certificat local produit exactement le même blocage Gatekeeper qu'un `.dmg`
téléchargé au navigateur. Le propriétaire a arbitré sur une prémisse fausse.

## Deuxième correction : le message n'est pas « endommagé »

Testé sur cette machine avec un bundle signé par le certificat de `build.sh`
(`CERT_CN="Bouncer Local Signing"`), puis marqué en quarantaine web :

```
$ codesign --verify --strict -vv Test.app
Test.app: valid on disk
Test.app: satisfies its Designated Requirement

$ spctl --assess --type execute -vv Test.app
Test.app: rejected
origin=Bouncer Local Signing

$ gktool scan Test.app
Scan completed, but failed because the software is not signed by a
distributor that meets the system Gatekeeper requirements.
```

La signature est valide. Gatekeeper refuse pour cause de distributeur non
reconnu, pas de corruption. « Bouncer est endommagé » est le message des
signatures cassées ou absentes ; ici l'utilisateur verra plutôt « macOS n'a pas
pu vérifier que Bouncer ne contient pas de logiciel malveillant ».

La différence compte : ce refus-là garde une porte de sortie dans Réglages →
Confidentialité et sécurité → « Ouvrir quand même », que le message
« endommagé » n'a pas. Sur Sequoia le clic droit → Ouvrir ne suffit plus, mais
le passage par les Réglages fonctionne toujours.

Je n'ai pas pu produire la boîte de dialogue elle-même en session sans écran :
ce qui est prouvé, c'est le verdict de Gatekeeper et son motif.

## Troisième correction : le seuil de notoriété n'est plus le sujet

Le seuil existe, et je l'ai vérifié dans `docs/Package-Acceptance-Policy.md:31-32` :

- 30 forks, 30 watchers ou 75 étoiles ;
- 90 forks, 90 watchers ou 225 étoiles si c'est le propriétaire du dépôt qui
  soumet lui-même.

Mais il arrive après un critère que Bouncer ne peut pas remplir. `cask/audit.rb`
lance `gktool scan` sur chaque artefact `App` et, en cas d'échec sur un tap
officiel, ajoute : « The homebrew/cask tap requires all casks to be signed and
notarized by Apple. » Les casks qui échouent au test Gatekeeper sont dépréciés
puis supprimés (`docs/Homebrew-Security-and-Supply-Chain.md:216`).

Sans Developer ID et sans notarisation, Bouncer est inéligible à
`homebrew/cask` quel que soit son nombre d'étoiles. Le tap personnel n'est pas
une étape avant le dépôt officiel, c'est la destination.

## Ce qui marche

### Recommandation : tap personnel + `postflight` qui retire la quarantaine

Le flag utilisateur a disparu, mais la strophe `postflight` du DSL
(`cask/dsl/postflight.rb`) permet à l'auteur du cask d'exécuter une commande
après l'installation. Un `xattr -dr` sur l'app installée rend à l'utilisateur
le « une seule commande, ça se lance ».

Dis-le franchement au propriétaire : c'est un contournement de Gatekeeper que
nous écrivons nous-mêmes. Homebrew a retiré `--no-quarantine` pour empêcher
exactement ça côté utilisateur. Ça ne passera jamais dans `homebrew/cask`, et
un tap personnel n'est pas surveillé. Le seul chemin qui ne contourne rien
reste le Developer Program à 99 €/an.

Dépôt à créer : `donpaco13/homebrew-tap`, fichier `Casks/bouncer.rb`.

```ruby
cask "bouncer" do
  version "0.1.0"
  sha256 "<sha256 du dmg>"

  url "https://github.com/donpaco13/bouncer/releases/download/v#{version}/Bouncer-#{version}.dmg"
  name "Bouncer"
  desc "Arbitre l'affichage de l'encoche entre plusieurs applications"
  homepage "https://github.com/donpaco13/bouncer"

  depends_on macos: ">= :sonoma"

  app "Bouncer.app"

  # Bouncer est signé par un certificat local, pas par un Developer ID Apple.
  # Sans ça, Gatekeeper bloque au premier lancement : « macOS n'a pas pu
  # vérifier que Bouncer ne contient pas de logiciel malveillant ».
  # À supprimer le jour où l'app est notarisée.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Bouncer.app"]
  end

  uninstall quit: "io.github.donpaco13.bouncer"

  zap trash: [
    "~/Library/Preferences/io.github.donpaco13.bouncer.plist",
    "~/Library/Application Support/Bouncer",
  ]
end
```

Le nom du dépôt doit commencer par `homebrew-` ; `brew` complète tout seul.
Côté utilisateur, une seule commande :

```
brew install --cask donpaco13/tap/bouncer
```

Aucun critère de notoriété, aucune revue, pas de `brew tap` préalable.

### Si le propriétaire refuse aussi le contournement

Alors le cask installe une app que macOS bloquera, et la levée revient à
l'utilisateur. À écrire sur la landing page, en deux lignes :

```
brew install --cask donpaco13/tap/bouncer
xattr -dr com.apple.quarantine /Applications/Bouncer.app
```

Ou, sans terminal : ouvrir l'app une fois, laisser macOS refuser, puis
Réglages → Confidentialité et sécurité → « Ouvrir quand même ».

C'est la même opération que le `postflight`, faite à la main. Le seul gain est
que l'utilisateur voit ce qu'il autorise.

### Ce que j'écarte

Une **formule** plutôt qu'un cask éviterait la quarantaine sans rien retirer :
`download_strategy.rb` ne contient aucune référence à la quarantaine, les
formules ne la posent jamais. Mais c'est le même contournement par une porte
dérobée, avec en prime une sémantique détournée (une formule n'installe pas
dans `/Applications`) et une UX moins bonne. Le `postflight` a le mérite de
dire ce qu'il fait.

## Un point à vérifier avant de publier

`build.sh` prévient que le certificat auto-signé doit être trusté dans le
trousseau, sinon TCC retombe sur le CDHash et l'autorisation Accessibilité ne
tient pas. Sur la machine de l'utilisateur, ce certificat ne sera jamais
trusté.

J'ai regardé la Designated Requirement effectivement embarquée par
`codesign --sign "Bouncer Local Signing"` :

```
designated => identifier "io.github.donpaco13.bouncer"
              and certificate leaf = H"30b315389485f49618366da1b4d2adba1e408c86"
```

C'est une comparaison de hash, pas une validation de chaîne de confiance : elle
n'a pas besoin que le certificat soit trusté sur la machine cible, et elle est
stable d'un build à l'autre. L'autorisation Accessibilité devrait donc tenir
chez l'utilisateur.

« Devrait » : le trust local reste nécessaire au moment de signer, et seule une
installation sur une machine vierge le prouvera. À tester avant le premier
lancement public, parce que c'est le mécanisme central de Bouncer.
