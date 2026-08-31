# Draft issue — à ouvrir AVANT la PR

`CONTRIBUTING.md` demande explicitement d'ouvrir une issue pour discuter d'une
feature avant de la coder. Le template d'issue « Feature request » du dépôt
attend les rubriques ci-dessous.

Une fois l'issue ouverte, remplacer `#XXXX` dans `PR.md` par son numéro.

---

**Titre :** `[FEATURE] A way to hide the notch without quitting the app`

**Is your feature request related to a problem?**

There is no way to get the notch out of the way for a moment. The windows sit
in a private CGS space, so `System Events`, `osascript`, Accessibility and
`NSApplication.hide:` all fail silently on them — the only way to reclaim that
strip of screen is to quit boring.notch and relaunch it later, which loses the
media session and the shelf.

**Describe the solution you'd like**

One primitive that orders the notch windows out and back in, reachable three ways:

- a Hide/Show Notch item in the menu bar
- a keyboard shortcut, which is the second half of what #1176 asks for
- a `boringnotch://hide` / `show` / `toggle` URL scheme

The hidden state would not be persisted, so the notch always comes back on the
next launch and nobody can end up stuck with a notch they can't restore.

**Use cases & user scenarios**

- Recording a screen capture or a demo where the notch overlaps the top strip
- A full-screen app whose controls sit under the notch (#1278)
- Presenting or screen-sharing, where the notch shows what you're listening to
- Running a second notch app: a URL scheme lets it hand the space over instead
  of asking people to quit one of the two
- Shortcuts, Raycast, BetterTouchTool and Keyboard Maestro can all trigger a URL

**Willingness to contribute**

Yes, I can write the code for this feature. A patch against `dev` is ready:
89 lines added across 4 files, no new dependency, no translation change.
