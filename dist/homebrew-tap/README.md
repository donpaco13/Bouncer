# homebrew-tap

Casks Homebrew de [donpaco13](https://github.com/donpaco13).

## Bouncer

[Bouncer](https://github.com/donpaco13/Bouncer) choisit quelle app d'encoche s'affiche sur un MacBook. Il en faut une version de macOS 14 ou plus récente, et un MacBook avec encoche.

```bash
brew install --cask donpaco13/tap/bouncer
```

Bouncer arrive dans `/Applications` et s'ouvre normalement. Le cask retire lui-même l'attribut de quarantaine, parce que l'app n'est pas notarisée par Apple. Détails : [docs/distribution/INSTALLATION.md](https://github.com/donpaco13/Bouncer/blob/main/docs/distribution/INSTALLATION.md).

Désinstaller :

```bash
brew uninstall --cask --zap donpaco13/tap/bouncer
```

`--zap` supprime aussi les préférences (`~/Library/Preferences/io.github.donpaco13.bouncer.plist`).

---

Homebrew casks by [donpaco13](https://github.com/donpaco13).

**Bouncer** picks which notch app shows on a notched MacBook (macOS 14+).

```bash
brew install --cask donpaco13/tap/bouncer
```

The app is not notarised by Apple, so the cask strips the quarantine attribute itself. Uninstall with `brew uninstall --cask --zap donpaco13/tap/bouncer`.
