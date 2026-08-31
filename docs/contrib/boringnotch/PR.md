# Draft PR — corps prêt à coller

- **Base :** `TheBoredTeam/boring.notch` branche `dev` (jamais `main`, cf. CONTRIBUTING)
- **Branche de travail :** `feature/notch-visibility-control`
- **Titre :** `Add a way to hide and show the notch`

Avant de coller : remplacer `#XXXX` par le numéro de l'issue ouverte depuis
`ISSUE.md`, et joindre les captures / la vidéo (le template de PR les exige).

---

## Corps de la PR

Closes #XXXX

### What this does

Today there is no way to get the notch out of the way for a moment. The windows
are pinned to a private CGS space, so `NSApplication.hide:`, Accessibility and
`osascript` all fail silently on them, and quitting the app is the only way to
reclaim that strip of screen.

This adds one primitive, `setNotchHidden(_:)`, and three ways to reach it:

- a **Hide/Show Notch** item in the menu bar
- a **keyboard shortcut** under Settings → Shortcuts, with no default binding so
  it doesn't take a combo from anyone
- a **`boringnotch://` URL scheme** with `hide`, `show` and `toggle`

```bash
open -g "boringnotch://hide"
open -g "boringnotch://show"
open -g "boringnotch://toggle"
```

That last one is what makes boring.notch scriptable from Shortcuts, Raycast,
BetterTouchTool, Keyboard Maestro, or another notch app that wants to hand the
space back and forth instead of asking people to quit one of the two.

### How it works

`setNotchHidden(_:)` orders the notch windows out rather than closing them, so
the view models, the media observers and the notch space membership survive
untouched and showing again is instant, with whatever was playing still there.

`createBoringNotchWindow` now checks the flag before ordering a new window
front. That is what keeps the state correct through the paths that rebuild
windows behind your back: a display being plugged in, screen lock with
*Show on lock screen* off, and the *Show on all displays* toggle.

The hidden state is deliberately **not** persisted. The notch always comes back
on the next launch, so a script or a mis-typed shortcut can't leave someone with
a notch they don't know how to restore.

Along the way this revives `togglePopover(_:)`. It was dead code, never called
from anywhere, and it only ever handled the single-display window — it now goes
through the same primitive and covers both display modes.

### Scope

- 89 lines added across 4 files
- No new dependency
- No translation change: the two new strings are English literals in code, so
  Crowdin picks them up from `dev` as usual

### Testing

<!-- Remplacer ce bloc par ce que tu as réellement vérifié, plus une capture ou
     une vidéo du menu bar item — le template de PR les demande. -->

- Menu bar item hides and shows the notch; the label follows the state
- `open -g "boringnotch://hide"` and `…//show` from Terminal
- Shortcut recorded in Settings → Shortcuts, then pressed
- Hidden, then plugged in a second display: notch stays hidden on both
- Hidden, then toggled *Show on all displays*: notch stays hidden
- Hidden, then locked and unlocked the screen: notch stays hidden
- Shown again: media keeps playing, the shelf still holds what was in it
- Quit and relaunched while hidden: notch is back

### Follow-ups I left out on purpose

- An App Intent, so the same three commands show up in the Shortcuts app
  natively. The URL scheme already covers it through the *Open URL* action.
- Auto-hide on full screen (#1278) could sit on top of this primitive.
