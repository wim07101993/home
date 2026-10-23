{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  alsa-lib,
  curl,
  freetype,
  gtk3,
  libx11,
  libxcursor,
  libxext,
  libxinerama,
  libxrandr,
  libxscrnsaver,
  dejavu_fonts,
  liberation_ttf,
}:

stdenv.mkDerivation {
  pname = "wing-edit";

  # Behringer's CDN puts every file under a hash of its own, so a newer
  # version's URL cannot be derived from this one: ./update.sh reads it off the
  # WING product page and rewrites these three lines.
  version = "3.3.3";
  src = fetchurl {
    url = "https://cdn-media.empowertribe.com/d8b54bb963e91c9baf1123827036faaf/Wing-Edit_LINUX_3.3.3.tar.gz";
    hash = "sha256-xtnCRh/msXrhXiSE3To/mx9dQjjPsuu/OErcNMMhRMA=";
  };

  # The binary and its manual sit at the top of the archive, in no directory.
  sourceRoot = ".";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = [
    alsa-lib
    curl
    freetype
    stdenv.cc.cc.lib
  ];

  # JUCE opens these by name at runtime instead of linking them.
  runtimeDependencies = [
    gtk3
    libx11
    libxcursor
    libxext
    libxinerama
    libxrandr
    libxscrnsaver
  ];

  # JUCE looks for fonts in the <dir> entries of /etc/fonts/fonts.conf. On NixOS
  # that names a minimal DejaVu only; the system's fonts are listed in conf.d,
  # which JUCE does not read.
  installPhase = ''
    runHook preInstall
    install -Dm755 WING-Edit $out/libexec/wing-edit/WING-Edit
    install -Dm644 Behringer_WING*.pdf -t $out/share/doc/wing-edit
    makeWrapper $out/libexec/wing-edit/WING-Edit $out/bin/wing-edit \
      --set-default JUCE_FONT_PATH "${dejavu_fonts}/share/fonts;${liberation_ttf}/share/fonts"
    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "wing-edit";
      desktopName = "WING Edit";
      comment = "Remote control for Behringer WING mixers";
      exec = "wing-edit";
      # The archive ships no icon.
      icon = "audio-card";
      categories = [ "Audio" "AudioVideo" ];
    })
  ];

  meta = {
    description = "Behringer's editor for the WING mixers";
    homepage = "https://www.behringer.com/en/wing/wing-black";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "wing-edit";
  };
}
