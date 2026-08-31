# Architecture Globale
+-------------------------------------------------------------+
|                        Bouncer Host                         |
|                                                             |
|  +---------------------+        +------------------------+  |
|  |   NotchOverlayView  |        |    WindowManager       |  |
|  |  (NSPanel / SwiftUI)|        |  (CGWindowList + AX)   |  |
|  +----------+----------+        +-----------+------------+  |
|             |                               |               |
|      Trackpad Swipe / Hover                 | Hide / Show   |
+-------------+-------------------------------+---------------+
              |                               |
              v                               v
    +-------------------+           +-------------------+
    |  Vibe Island.app  |           |  BoringNotch.app  |
    | (Fenêtre Visible) |           | (Fenêtre Masquée) |
    +-------------------+           +-------------------+


# Composants Systèmes
2.1 WindowManager (Détection & Contrôle)
	•	Identification : Utilise CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID).
	•	Filtre : Fenêtres dont le kCGWindowBounds intersecte la zone de l'encoche (NSScreen.main.safeAreaInsets.top).
	•	Ignore notre propre processus et les barres système.
	•	Masquage / Affichage :
	•	Obtention de l'élément cible : AXUIElementCreateApplication(pid).
	•	Contrôle via l'attribut kAXHiddenAttribute (true pour masquer, false pour afficher) ou manipulation directe de l'état de la fenêtre via l'arbre d'Accessibilité.
2.2 NotchOverlay (Capteur d'Événements)
	•	Type : NSPanel sans bordure (.borderless), transparent, non activable (.nonactivatingPanel).
	•	Window Level : .statusBar + 1 pour être positionné immédiatement au-dessus de l'encoche.
	•	Hit-Testing : Le panel laisse passer les clics vers l'application active sous-jacente (ignoresMouseEvents = false uniquement sur les zones de flèches au survol).
	•	Gestes : Détection du swipe 2 doigts via NSEvent.addLocalMonitorForEvents(matching: .scrollWheel).
2.3 Permissions & Sécurité
	•	Requiert l'autorisation d'Accessibilité macOS : AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true]).
	•	Pour la distribution hors Mac App Store : binaire signé avec Developer ID Application, Hardened Runtime activé, notarizé via xcrun notarytool.
# 

# Algorithme de Switch
	1	L'utilisateur déclenche un swipe à droite sur l'encoche.
	2	NotchOverlay intercepte l'événement de scroll horizontal (deltaX > seuil).
	3	WindowManager détermine l'application suivante dans la liste circulaire des apps détectées :
	•	Applique AXHidden = true sur l'application active courante.
	•	Applique AXHidden = false sur la nouvelle application cible.
	•	Met à jour l'index actif et affiche un indicateur visuel discret de transition (fade/spring).

