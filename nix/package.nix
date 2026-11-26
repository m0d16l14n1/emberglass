{ lib, stdenvNoCC, makeWrapper, python3, coreutils, gnused, gnugrep, procps, systemd }:

stdenvNoCC.mkDerivation {
  pname = "emberglass";
  version = "1.0.0";
  src = lib.cleanSource ../.;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 emberglass-sampler $out/lib/emberglass/emberglass-sampler
    install -Dm755 emberglass $out/bin/emberglass
    wrapProgram $out/bin/emberglass --prefix PATH : ${lib.makeBinPath [ python3 coreutils gnused gnugrep procps systemd ]}
    mkdir -p $out/share/plasma/plasmoids
    cp -R plasma/org.emberglass.sensors $out/share/plasma/plasmoids/
    runHook postInstall
  '';
  meta = {
    description = "Apple silicon sensors in your panel: KDE Plasma widget, Waybar module, MangoHud line";
    homepage = "https://github.com/m0d16l14n1/emberglass";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    mainProgram = "emberglass";
  };
}
