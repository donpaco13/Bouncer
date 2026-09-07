cask "bouncer" do
  version "0.1.0"
  sha256 "606c0ebc920d92ee0cb5bcfae4e52fd6dde2e2877d6054f174c27d63910d5d27"

  url "https://github.com/donpaco13/Bouncer/releases/download/v#{version}/Bouncer-#{version}.zip"
  name "Bouncer"
  desc "Arbitre l'affichage de l'encoche entre plusieurs applications"
  homepage "https://github.com/donpaco13/Bouncer"

  # LSMinimumSystemVersion vaut 14.0 dans l'Info.plist écrit par build.sh.
  depends_on macos: :sonoma

  app "Bouncer.app"

  # Bouncer est signée par un certificat local, pas par un Developer ID Apple. Homebrew met
  # tous les casks en quarantaine sans exception depuis la 4.7.0, et `--no-quarantine` a été
  # supprimé le 2026-07-30 (voir docs/DISTRIBUTION.md) : sans ce postflight, Gatekeeper bloque
  # au premier lancement avec « macOS n'a pas pu vérifier que Bouncer ne contient pas de
  # logiciel malveillant ».
  # C'est un contournement de Gatekeeper que nous écrivons nous-mêmes, assumé comme tel.
  # À supprimer le jour où l'app est notarisée.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Bouncer.app"]
  end

  uninstall quit: "io.github.donpaco13.bouncer"

  # Bouncer n'écrit que dans UserDefaults, jamais sur disque en direct. Huit clés actives, toutes
  # préfixées `bouncer.` et toutes dans ce seul plist : `bundleIDsApprises.v3` (CatalogueApps.swift),
  # `accueilVu` (FenetreAccueil.swift), `raccourciGlobal` (RaccourciGlobal.swift), et les cinq
  # préférences de Reglages.swift — `modeActivation`, `porteeApproche`, `margeLaterale`,
  # `intervalleRafraichissement`, `bundleIDsExclus`.
  #
  # Ne pas lister les clés purgées (`bundleIDsApprises`, `bundleIDsApprises.v2`) : elles sont
  # effacées par `CatalogueApps.init()`, et de toute façon `zap` jette le plist entier.
  # Inventaire à revérifier d'un `grep -rhoE '"bouncer\.[A-Za-z0-9._]+"' Sources/` avant chaque
  # release — c'est ce qui manquait la fois où il annonçait deux clés sur sept.
  zap trash: "~/Library/Preferences/io.github.donpaco13.bouncer.plist"
end
