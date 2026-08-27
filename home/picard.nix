{ pkgs, ... }:

let
  picard-wrapped = pkgs.picard.overridePythonAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.wrapGAppsHook3 ];
    buildInputs = (old.buildInputs or []) ++ [ pkgs.gsettings-desktop-schemas ];
  });
in

{
  home.packages = with pkgs; [
    picard-wrapped
  ];
}
