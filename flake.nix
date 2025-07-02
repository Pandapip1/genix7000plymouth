{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    genix7000 = {
      url = "github:cab404/genix7000";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      let
        inherit (nixpkgs) lib;
        genix-to-image =
          pkgs:
          pkgs.writeScriptBin "to-image" (
            builtins.replaceStrings
              [
                "./genix.scad"
                "openscad"
                "/usr/bin/env nu"
              ]
              [
                "${inputs.genix7000}/genix.scad"
                (lib.getExe pkgs.openscad-unstable-fhs) # Latest stable (from 2021!) has a bug relevant to this project
                (lib.getExe pkgs.nushell)
              ]
              (builtins.readFile "${inputs.genix7000}/to-image.nu")
          );
        mkGenixFrame =
          pkgs:
          {
            name,
            numLambdas ? 6,
            lambdaThickness ? 20,
            imageWidth ? 256,
            imageHeight ? 256,
            offsetX ? -24,
            offsetY ? -42,
            gapsX ? 3,
            gapsY ? -5,
            rotation ? 0,
            angle ? 30,
            clipRadius ? 92,
            clipRotation ? 0,
            clipInverse ? false,
            colors ? [
              "#5277C3"
              "#7CAEDC"
            ],
          }:
          pkgs.runCommand name
            {
              nativeBuildInputs = [
                (genix-to-image pkgs)
              ];
            }
            ''
              to-image \
                --num ${toString numLambdas} \
                --thick ${toString lambdaThickness} \
                --imgsize "${toString imageWidth},${toString imageHeight}" \
                --offset "${toString offsetX},${toString offsetY}" \
                --gaps "${toString gapsX},${toString gapsY}" \
                --rotation ${toString rotation} \
                --angle ${toString angle} \
                --clipr ${toString clipRadius} \
                --cliprot ${toString clipRotation} \
                --clipinv ${if clipInverse then "true" else "false"} \
                ./tmp.png \
                ${builtins.concatStringsSep " " (map (color: "\"${color}\"") colors)}
              mv ./tmp.png $out
            '';
        mkGenixPlymouthTheme =
          pkgs:
          {
            name,
            animation,
            frameRate ? 15,
            duration ? 4,
          }:
          pkgs.runCommand name { } (
            ''
              mkdir -p $out/share/plymouth/themes/${name}
            ''
            + (builtins.concatStringsSep "\n" (
              map (
                frame:
                "cp ${
                  mkGenixFrame pkgs (
                    (animation (frame / (frameRate + 0.0))) // { name = "${name}-frame-${toString frame}.png"; }
                  )
                } $out/share/plymouth/themes/${name}/frame-${toString frame}.png"
              ) (lib.range 0 (frameRate * duration - 1))
            ))
          );
      in
      {
        systems = nixpkgs.lib.platforms.linux;
        perSystem =
          { system, pkgs, ... }:
          {
            _module.args.pkgs = import nixpkgs {
              inherit system;
              overlays = [
                (final: prev: {
                  openscad-unstable-fhs = prev.buildFHSEnv (rec {
                    name = "openscad-fhs";

                    mesaDrivers = with prev; [
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

                    targetPkgs =
                      pkgs:
                      [
                        pkgs.openscad-unstable
                      ]
                      ++ mesaDrivers;

                    runScript = "openscad";

                    profile = ''
                      export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib
                      export LD_LIBRARY_PATH=/run/opengl-driver/lib:${lib.makeLibraryPath mesaDrivers}:$LD_LIBRARY_PATH
                    '';

                    extraInstallCommands = ''
                      mkdir -p $out/run/opengl-driver
                      ln -s ${prev.mesa}/lib $out/run/opengl-driver/lib
                    '';
                  });
                })
              ];
            };
            packages = {
              testGenixFrame = mkGenixFrame pkgs { name = "test-genix-frame.png"; };
              testGenixPlymouthTheme = mkGenixPlymouthTheme pkgs {
                name = "test-genix-plymouth-theme";
                animation = time: {
                  # Wait WTF nix doesn't have ANY common math stuff?!
                  lambdaThickness = builtins.floor (if time <= 1 then 20 + time * 100 else 20 + (2 - time) * 100);
                  rotation = builtins.floor (if time <= 1 then time * 180 else (2 - time) * 180);
                };
                frameRate = 5;
                duration = 2;
              };
            };
          };
        flake = {
          nixosModules = {
            genix7000 =
              { config, pkgs, ... }:
              {
                options =
                  let
                    argsType = lib.types.submodule {
                      options = {
                        numLambdas = lib.mkOption {
                          type = lib.types.addCheck lib.types.int (x: x >= 3 && x <= 25);
                          default = 6;
                          description = "Number of lambdas";
                        };
                        lambdaThickness = lib.mkOption {
                          type = lib.types.int;
                          default = lib.types.addCheck lib.types.int (x: x >= 5 && x <= 30);
                          description = "Lambda thickness (unknown units)";
                        };
                        imageWidth = lib.mkOption {
                          type = lib.types.int;
                          default = 256;
                          description = "Image width (in px)";
                        };
                        imageHeight = lib.mkOption {
                          type = lib.types.int;
                          default = 256;
                          description = "Image height (in px)";
                        };
                        offsetX = lib.mkOption {
                          type = lib.types.int;
                          default = -24;
                          description = "X offset of lambda (unknown units)";
                        };
                        offsetY = lib.mkOption {
                          type = lib.types.int;
                          default = -42;
                          description = "Y offset of lambda (unknown units)";
                        };
                        gapsX = lib.mkOption {
                          type = lib.types.int;
                          default = -24;
                          description = "X offset after clipping (use for gaps) (unknown units)";
                        };
                        gapsY = lib.mkOption {
                          type = lib.types.int;
                          default = -42;
                          description = "Y offset after clipping (use for gaps) (unknown units)";
                        };
                        rotation = lib.mkOption {
                          type = lib.types.addCheck lib.types.int (x: x >= -180 && x <= 180);
                          default = 0;
                          description = "Rotation of each lambda (in degrees)";
                        };
                        angle = lib.mkOption {
                          type = lib.types.addCheck lib.types.int (x: x >= -180 && x <= 180);
                          default = 30;
                          description = "Lambda arm angle (in degrees)";
                        };
                        clipRadius = lib.mkOption {
                          type = lib.types.addCheck lib.types.int (x: x >= 0 && x <= 300);
                          default = 92;
                          description = "Clipping n-gon radius (unknown units)";
                        };
                        clipRotation = lib.mkOption {
                          type = lib.types.addCheck lib.types.int (x: x >= -180 && x <= 180);
                          default = 0;
                          description = "Clipping n-gon rotation (in degrees)";
                        };
                        clipInverse = lib.mkOption {
                          type = lib.types.boolean;
                          default = false;
                          description = "Reverse clipping order";
                        };
                        colors = lib.mkOption {
                          type = lib.types.listOf (
                            lib.types.addCheck lib.types.str (
                              str:
                              (lib.hasPrefix "#" str)
                              && (lib.stringLength str == 7)
                              && (lib.match "^[0-9a-fA-F]+$" (lib.substring 1 (lib.stringLength str - 1) str) != null)
                            )
                          );
                          default = [
                            "#5277C3"
                            "#7CAEDC"
                          ];
                          description = "Color palette to use";
                        };
                      };
                    };
                  in
                  {
                    boot.plymouth.genix7000 = {
                      enable = lib.mkEnableOption "automatically generated genix7000 boot animations";
                      animation = lib.mkOption {
                        type = lib.types.functionTo argsType;
                        example = ''
                          time: {
                            lambdaThickness = builtins.floor (if time <= 1 then 20 + time * 100 else 20 + (2 - time) * 100);
                            rotation = builtins.floor (if time <= 1 then time * 180 else (2 - time) * 180);
                          };
                        '';
                        description = "A function that takes the frame time and returns a set of parameters to pass to to-image";
                      };
                      defaults = lib.mkOption {
                        type = argsType;
                        example = {
                          imageWidth = 64;
                          imageHeight = 64;
                        };
                        description = "a default set of parameters to pass to to-image";
                      };
                      frameRate = lib.mkOption {
                        type = lib.types.int;
                        default = 15;
                        description = "The frame rate (in frames per second) of the animation";
                      };
                      duration = lib.mkOption {
                        type = lib.types.int;
                        example = 4;
                        description = "The length (in seconds) of the animation";
                      };
                    };
                  };
                config =
                  let
                    cfg = config.boot.plymouth.genix7000;
                  in
                  lib.mkIf cfg.enable {
                    boot.plymouth = {
                      themePackages = [
                        (mkGenixPlymouthTheme pkgs {
                          name = "genix7000-autogenerated-theme";
                          animation = time: cfg.defaults // (cfg.animation time);
                          inherit (cfg) frameRate duration;
                        })
                      ];
                      theme = "genix7000-autogenerated-theme";
                    };
                  };
              };
          };
        };
      }
    );
}
