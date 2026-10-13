# Checklist de sortie, Bouncer v0.1.0 (non signée)

Tout est prêt. Il ne reste que les gestes publics, dans cet ordre. Chaque geste a sa ligne « Défaire ».

Archive prévue : `dist/Bouncer-0.1.0.zip`
sha256 : `764419c69874124ab9ad4f3eb1e843046b3c4d7762c052d27a3427ab2921e6da`

```bash
export V=0.1.0
cd /Users/francoishatem/HarnessAgents/worktrees/worker-bouncer-release-v0-1   # ou le repo une fois la branche intégrée
```

## 0. Avant de toucher à quoi que ce soit

1. L'archive est toujours là et correspond au cask :
   ```bash
   shasum -a 256 dist/Bouncer-$V.zip
   grep -E '^  (version|sha256)' Casks/bouncer.rb
   ```
   Les deux sha256 doivent être identiques. Si `dist/` a disparu, `./release.sh` refabrique l'archive et réécrit le cask. Le sha256 change alors (build non reproductible) : recopie le nouveau dans `dist/homebrew-tap/Casks/bouncer.rb`, et dans `dist/RELEASE-NOTES-v0.1.0.md` (deux occurrences).
   **Défaire :** rien, lecture seule.
2. Tu es connecté à GitHub : `gh auth status`.
   **Défaire :** rien.

## 1. Mettre le code sur `main`

3. Intégrer la branche `agent/worker-bouncer-release-v0-1` dans `main` (god s'en charge), puis `git push origin main`. Le cask `Casks/bouncer.rb` et la landing partent avec.
   **Défaire :** `git revert -m 1 <merge>` puis `git push origin main`. Un `push --force` n'est pas nécessaire.

## 2. Rendre le dépôt public

4. ```bash
   gh repo edit donpaco13/Bouncer --visibility public --accept-visibility-change-consequences
   ```
   **Défaire :** `gh repo edit donpaco13/Bouncer --visibility private --accept-visibility-change-consequences`. Attention : ce qui a été vu pendant que le dépôt était public (clones, forks, caches) ne se reprend pas.

## 3. La release

5. Tag et push :
   ```bash
   git tag "v$V" && git push origin "v$V"
   ```
   **Défaire :** `git push --delete origin "v$V" && git tag -d "v$V"`
6. Release avec l'archive et les notes :
   ```bash
   gh release create "v$V" "dist/Bouncer-$V.zip" --title "Bouncer $V" --notes-file dist/RELEASE-NOTES-v0.1.0.md
   ```
   **Défaire :** `gh release delete "v$V" --yes --cleanup-tag`
7. L'archive est téléchargeable et identique :
   ```bash
   curl -sIL "https://github.com/donpaco13/Bouncer/releases/download/v$V/Bouncer-$V.zip" | grep -E "^HTTP|content-length"
   curl -sL "https://github.com/donpaco13/Bouncer/releases/download/v$V/Bouncer-$V.zip" | shasum -a 256
   ```
   Le dernier sha256 doit être celui du haut de ce fichier.
   **Défaire :** rien, lecture seule.

## 4. Le tap

Le tap part après la release : tant que l'archive n'est pas en ligne, `brew install` échoue au téléchargement.

8. Créer le dépôt et pousser le contenu préparé :
   ```bash
   rm -rf /tmp/homebrew-tap && cp -R dist/homebrew-tap /tmp/homebrew-tap && cd /tmp/homebrew-tap
   git init -b main && git add . && git commit -m "bouncer $V"
   gh repo create donpaco13/homebrew-tap --public --description "Casks Homebrew de donpaco13" --source=. --push
   cd -
   ```
   **Défaire :** `gh repo delete donpaco13/homebrew-tap --yes` (demande le scope `delete_repo` : `gh auth refresh -s delete_repo`).

## 5. Smoke test

9. ```bash
   brew untap donpaco13/tap 2>/dev/null; brew tap donpaco13/tap
   brew audit --cask donpaco13/tap/bouncer
   mv /Applications/Bouncer.app /tmp/Bouncer.app.dev   # si tu as la version de dev installée
   brew install --cask donpaco13/tap/bouncer
   xattr -lr /Applications/Bouncer.app | grep -i quarantine   # ne doit rien afficher
   codesign --verify --strict -v /Applications/Bouncer.app
   open /Applications/Bouncer.app
   ```
   **Défaire :** `brew uninstall --cask --zap donpaco13/tap/bouncer && brew untap donpaco13/tap`, puis `mv /tmp/Bouncer.app.dev /Applications/Bouncer.app`. `--zap` supprime aussi tes préférences Bouncer.
10. À la main : autoriser l'Accessibilité, balayer l'encoche à deux doigts, vérifier que la bascule marche. Le vrai test d'une installation propre se fait sur une machine qui n'a jamais eu le certificat `Bouncer Local Signing`.
    **Défaire :** `tccutil reset Accessibility io.github.donpaco13.bouncer`
11. Le comportement du zip direct (le texte de la landing) : télécharge l'archive dans Safari sur une autre machine ou un autre compte, ouvre-la. macOS doit refuser avec « macOS n'a pas pu vérifier… », puis Réglages Système, Confidentialité et sécurité, **Ouvrir quand même** doit la lancer.
    **Défaire :** rien.

## 6. La landing

La landing affiche la commande `brew` en première ligne : on la publie après l'étape 9.

12. Activer Pages avec la source « GitHub Actions » :
    ```bash
    gh api -X POST repos/donpaco13/Bouncer/pages -f build_type=workflow
    ```
    **Défaire :** `gh api -X DELETE repos/donpaco13/Bouncer/pages`
13. Lancer le déploiement (le workflow `landing-pages.yml` se lance aussi à chaque push sur `main` qui touche `landing/`) :
    ```bash
    gh workflow run landing-pages.yml && sleep 5 && gh run watch "$(gh run list --workflow landing-pages.yml --limit 1 --json databaseId -q '.[0].databaseId')"
    ```
    **Défaire :** étape 12 (Pages désactivé, le site disparaît).
14. Vérifier :
    ```bash
    curl -sI https://donpaco13.github.io/Bouncer/en/ | head -1
    curl -s https://donpaco13.github.io/Bouncer/en/ | grep -o 'releases/download/v0.1.0/Bouncer-0.1.0.zip' | head -1
    curl -s https://donpaco13.github.io/Bouncer/en/ | grep -o 'brew install --cask donpaco13/tap/bouncer' | head -1
    ```
    Attendu : `HTTP/2 200`, puis les deux chaînes.
    **Défaire :** rien, lecture seule.

## Hors checklist

- Aucune notarisation Apple (décision : sortie non signée). Le `postflight_steps` du cask est le contournement assumé.
- La vidéo de 8 s de la landing a un emplacement prévu et n'est pas tournée.
- Le sha256 ci-dessus vaut pour cette archive précise. Toute reconstruction oblige à refaire l'étape 0.
