# Publier Bouncer

Une ligne à la fois, dans cet ordre. `⌨` = à faire à la main, pas de commande.

```bash
export V=0.1.0
```

## 1. La version

1. ⌨ Dans `build.sh`, mettre `VERSION="$V"` (ligne 9). C'est le seul endroit où la version est écrite.
2. `grep -n "$V" build.sh`
3. `swift test`

## 2. L'artefact et le cask

4. `./release.sh`
5. `shasum -a 256 "dist/Bouncer-$V.zip"`
6. `grep -E '^  (version|sha256)' Casks/bouncer.rb`
7. ⌨ Vérifier que le sha256 des étapes 5 et 6 est le même.
8. `git add build.sh Casks/bouncer.rb && git commit -m "Release v$V"`

## 3. Le dépôt public (une seule fois)

9. `gh repo edit donpaco13/Bouncer --visibility public --accept-visibility-change-consequences`
10. `gh repo create donpaco13/homebrew-tap --public --description "Casks Homebrew de donpaco13"`

## 4. La release

11. `git push origin main`
12. `git tag "v$V" && git push origin "v$V"`
13. `gh release create "v$V" "dist/Bouncer-$V.zip" --title "Bouncer $V" --notes-file dist/RELEASE-NOTES-v$V.md`
14. `curl -sIL "https://github.com/donpaco13/Bouncer/releases/download/v$V/Bouncer-$V.zip" | grep -E "^HTTP|content-length"`

## 5. Le tap

Le cask part **après** la release : tant que l'archive n'est pas en ligne, `brew install` échoue au téléchargement.

15. `gh repo clone donpaco13/homebrew-tap /tmp/homebrew-tap`
16. `mkdir -p /tmp/homebrew-tap/Casks && cp Casks/bouncer.rb /tmp/homebrew-tap/Casks/`
17. `git -C /tmp/homebrew-tap add Casks/bouncer.rb && git -C /tmp/homebrew-tap commit -m "bouncer $V"`
18. `git -C /tmp/homebrew-tap push`

## 6. La vérification

19. `brew untap donpaco13/tap 2>/dev/null; brew tap donpaco13/tap`
20. `brew audit --cask donpaco13/tap/bouncer`
21. `rm -rf /Applications/Bouncer.app`
22. `brew install --cask donpaco13/tap/bouncer`
23. `xattr -lr /Applications/Bouncer.app | grep -i quarantine` — doit ne rien afficher.
24. `codesign --verify --strict -v /Applications/Bouncer.app`
25. `open /Applications/Bouncer.app`
26. ⌨ Autoriser l'Accessibilité, faire un swipe sur l'encoche, vérifier que la bascule marche.

## 7. La landing

27. ⌨ Déployer la landing **après** l'étape 22 : elle affiche la commande `brew` en première ligne.

## Ce qui n'est pas automatisable

- ⌨ La notarisation Apple : décision en attente (99 €/an). Sans elle, le `postflight` du cask reste nécessaire.
- ⌨ Le premier lancement sur une **machine vierge** : c'est le seul test qui prouve que l'autorisation d'Accessibilité tient chez quelqu'un dont le trousseau n'a pas le certificat `Bouncer Local Signing`.
- ⌨ Les notes de release (`dist/RELEASE-NOTES-v$V.md`), à écrire avant l'étape 14.

## Sauvegarder l'identité de signature

La designated requirement de chaque copie installée épingle le hash du certificat `Bouncer Local Signing` (`SIGNING_PIN` dans `release.sh`). Si la clé est perdue, toute release suivante fait perdre l'Accessibilité à tous les utilisateurs. `./release.sh` refuse alors de créer un nouveau certificat : il faut réimporter la sauvegarde.

- ⌨ Export, une fois : Trousseaux d'accès > session > Mes certificats > clic droit sur `Bouncer Local Signing` > Exporter, format `.p12`, mot de passe fort. Ranger le fichier et le mot de passe hors du Mac. (`security export -t identities` exporterait toutes les identités du trousseau, pas seulement celle-ci.)
- Réimport (demande le mot de passe) : `security import bouncer-signing.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign`
- Contrôle : `security find-certificate -c "Bouncer Local Signing" -Z | grep SHA-1` doit afficher `30B315389485F49618366DA1B4D2ADBA1E408C86`.

## Rollback

```bash
gh release delete "v$V" --yes
git push --delete origin "v$V"
git -C /tmp/homebrew-tap revert --no-edit HEAD && git -C /tmp/homebrew-tap push
```
