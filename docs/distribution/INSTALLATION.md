# Installer Bouncer

## Avec Homebrew

```
brew install --cask donpaco13/tap/bouncer
```

Bouncer s'installe dans votre dossier Applications et s'ouvre normalement. Rien
d'autre à faire.

## Sans Homebrew

1. Téléchargez l'archive `.zip` depuis la page des versions.
2. Double-cliquez le fichier téléchargé.
3. Glissez `Bouncer` dans votre dossier Applications.

Au premier lancement, macOS refuse d'ouvrir l'app : « macOS n'a pas pu vérifier
que Bouncer ne contient pas de logiciel malveillant ».

macOS ne sait pas qui a écrit Bouncer. Apple facture 99 € par an aux
développeurs pour une signature qu'il reconnaît d'emblée, et Bouncer ne la paie
pas. Le blocage porte sur cette identité manquante, pas sur le contenu de l'app :
elle n'est ni endommagée ni infectée.

Pour l'ouvrir quand même, une seule fois :

1. Double-cliquez Bouncer et laissez macOS refuser.
2. Ouvrez Réglages Système, puis **Confidentialité et sécurité**.
3. Descendez jusqu'au message qui parle de Bouncer, cliquez sur **Ouvrir quand
   même**.
4. Confirmez avec votre mot de passe.

Les lancements suivants passent directement.

## Au premier lancement

Bouncer n'a ni icône dans le Dock ni fenêtre : elle vit dans la barre des menus,
en haut à droite de l'écran.

Une fenêtre s'ouvre la première fois pour vous montrer où la trouver, obtenir
l'autorisation macOS dont elle a besoin, et vous apprendre le geste qui la
commande : un swipe à deux doigts sur l'encoche.

## Désinstaller

```
brew uninstall --cask bouncer
```

Pour effacer aussi vos réglages :

```
brew uninstall --zap --cask bouncer
```

Sans Homebrew, glissez Bouncer de votre dossier Applications vers la corbeille.
