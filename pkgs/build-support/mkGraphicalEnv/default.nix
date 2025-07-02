{
  lib,
  buildFHSEnv,
  pkgs,
  mesa,
}:

oldDrv:
let
  mesaDrivers =
    pkgs': with pkgs'; [
      mesa
      libGL
      libglvnd
      xorg.libX11
      xorg.libXext
      xorg.libXdamage
      xorg.libXfixes
      xorg.libXxf86vm
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      wayland
    ];
in
buildFHSEnv {
  inherit (oldDrv)
    pname
    version
    meta
    ;

  targetPkgs =
    pkgs':
    [
      (oldDrv.override (
        lib.filterAttrs (
          name: value: lib.any (path': name == path') (lib.attrNames oldDrv.override.__functionArgs)
        ) pkgs'
      ))
    ]
    ++ mesaDrivers pkgs';

  runScript = lib.getExe oldDrv;
  executableName = oldDrv.meta.mainProgram;

  profile = ''
    export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib
    export LD_LIBRARY_PATH=/run/opengl-driver/lib:${lib.makeLibraryPath (mesaDrivers pkgs)}:$LD_LIBRARY_PATH
  '';

  extraInstallCommands = ''
    mkdir -p $out/run/opengl-driver
    ln -s ${mesa}/lib $out/run/opengl-driver/lib
  '';
}
