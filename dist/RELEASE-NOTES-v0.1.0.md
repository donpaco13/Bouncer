# Bouncer 0.1.0

## Français

Première version publique de Bouncer.

Bouncer décide quelle app d'encoche s'affiche sur ton MacBook. Vibe Island, boringNotch et les autres restent ouvertes, une seule se montre à la fois. Tu changes d'avis d'un balayage à deux doigts sur l'encoche, d'une flèche, d'un raccourci clavier ou depuis la barre des menus.

**Installer**

```bash
brew install --cask donpaco13/tap/bouncer
```

Ou télécharge `Bouncer-0.1.0.zip` ci-dessous, décompresse-le et glisse Bouncer dans Applications.

**Ce qu'il faut savoir**

- macOS 14 Sonoma ou plus récent, MacBook avec encoche.
- Bouncer demande l'autorisation Accessibilité. Sans elle, il ne touche à rien.
- L'app n'est pas notarisée par Apple (99 € par an que ce projet ne paie pas). Avec le zip, macOS affiche « macOS n'a pas pu vérifier que Bouncer ne contient pas de logiciel malveillant ». Pour l'ouvrir une fois : Réglages Système, Confidentialité et sécurité, **Ouvrir quand même**. Avec Homebrew, le cask retire la quarantaine lui-même et tu ne vois pas ce message.
- Sentry (rapports de plantage) est désactivé par défaut. Rien n'est envoyé tant que tu ne l'actives pas dans le menu de Bouncer. Détail dans [docs/CONFIDENTIALITE.md](https://github.com/donpaco13/Bouncer/blob/main/docs/CONFIDENTIALITE.md).
- Interface en français et en anglais.

**Vérifier l'archive**

```bash
shasum -a 256 Bouncer-0.1.0.zip
# 764419c69874124ab9ad4f3eb1e843046b3c4d7762c052d27a3427ab2921e6da
```

## English

First public release of Bouncer.

Bouncer decides which notch app shows on your MacBook. Vibe Island, boringNotch and the others stay open; one shows at a time. You switch with a two-finger swipe on the notch, an arrow, a keyboard shortcut, or the menu bar.

**Install**

```bash
brew install --cask donpaco13/tap/bouncer
```

Or download `Bouncer-0.1.0.zip` below, unzip it and drag Bouncer into Applications.

**Good to know**

- macOS 14 Sonoma or later, MacBook with a notch.
- Bouncer asks for the Accessibility permission. Without it, it touches nothing.
- The app is not notarised by Apple (€99 a year that this project doesn't pay). With the zip, macOS shows "macOS cannot verify that Bouncer is free of malware". To open it once: System Settings, Privacy & Security, **Open Anyway**. With Homebrew the cask strips the quarantine itself, so you never see that message.
- Sentry crash reporting is off by default. Nothing is sent until you turn it on in the Bouncer menu. Details in [docs/CONFIDENTIALITE.md](https://github.com/donpaco13/Bouncer/blob/main/docs/CONFIDENTIALITE.md) (French).
- The interface is in English and French.

**Verify the archive**

```bash
shasum -a 256 Bouncer-0.1.0.zip
# 764419c69874124ab9ad4f3eb1e843046b3c4d7762c052d27a3427ab2921e6da
```
