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
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      let
        lib' = nixpkgs.lib;
        overlay = final: prev: {
          lib = lib'.recursiveUpdate prev.lib {
            types = final.callPackage "${self}/lib/types.nix" { };
          };
          mkGraphicalEnv = final.callPackage "${self}/pkgs/build-support/mkGraphicalEnv" { };
          openscad-unstable-fhs =
            final.callPackage "${self}/pkgs/by-name/openscad-unstable-fhs/package.nix"
              { };
          genix-to-image = prev.writeScriptBin "to-image" (
            builtins.replaceStrings
              [
                "./genix.scad"
                "openscad"
                "/usr/bin/env nu"
              ]
              [
                ("${inputs.genix7000}/genix.scad")
                (prev.lib.getExe final.openscad-unstable-fhs) # Latest stable (from 2021!) has a bug relevant to this project
                (prev.lib.getExe prev.nushell)
              ]
              (builtins.readFile "${inputs.genix7000}/to-image.nu")
          );
          mkGenixFrame =
            name: rawArgs:
            let
              args = validateArgs rawArgs mkGenixFrameArgsType;
            in
            prev.runCommand name
              {
                nativeBuildInputs = [
                  final.genix-to-image
                ];
              }
              ''
                to-image \
                  --num ${toString args.numLambdas} \
                  --thick ${toString args.lambdaThickness} \
                  --imgsize "${toString args.imageWidth},${toString args.imageHeight}" \
                  --offset "${toString args.offsetX},${toString args.offsetY}" \
                  --gaps "${toString args.gapsX},${toString args.gapsY}" \
                  --rotation ${toString args.rotation} \
                  --angle ${toString args.angle} \
                  --clipr ${toString args.clipRadius} \
                  --cliprot ${toString args.clipRotation} \
                  --clipinv ${if args.clipInverse then "true" else "false"} \
                  "${name}" \
                  ${builtins.concatStringsSep " " (map (color: "\"${color}\"") args.colors)}
                mv ${name} $out
              '';
          mkGenixPlymouthTheme =
            {
              name,
              animation,
              duration,
              frameRate ? 15,
            }:
            prev.runCommand name { } (
              ''
                mkdir -p $out/share/plymouth/themes/${name}
              ''
              + (builtins.concatStringsSep "\n" (
                map (
                  frame:
                  "cp ${
                    final.mkGenixFrame "${name}-frame-${toString frame}.png" (animation (frame / (frameRate + 0.0)))
                  } $out/share/plymouth/themes/${name}/frame-${toString frame}.png"
                ) (prev.lib.range 0 (frameRate * duration - 1))
              ))
            );
        };
        # System doesn't matter here, only overlays do
        inherit (import nixpkgs { system = "x86_64-linux"; overlays = [ overlay ]; }) lib;
        validateArgs =
          args: argsType:
          (lib.evalModules {
            modules = [
              {
                options.args = lib.mkOption {
                  type = argsType;
                };
              }
              {
                config.args = args;
              }
            ];
          }).options.args.value;
        mkIntTypeBetween =
          start: end:
          lib.recursiveUpdate (lib.types.addCheck lib.types.int (x: x >= start && x <= end)) {
            description = "${lib.types.int.description} between ${toString start} and ${toString end}";
          };
        mkGenixFrameArgsType = lib.types.submodule {
          options = {
            numLambdas = lib.mkOption {
              type = mkIntTypeBetween 3 25;
              default = 6;
              description = "Number of lambdas";
            };
            lambdaThickness = lib.mkOption {
              type = mkIntTypeBetween 5 30;
              default = 20;
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
              default = 3;
              description = "X offset after clipping (use for gaps) (unknown units)";
            };
            gapsY = lib.mkOption {
              type = lib.types.int;
              default = -5;
              description = "Y offset after clipping (use for gaps) (unknown units)";
            };
            rotation = lib.mkOption {
              type = mkIntTypeBetween (-180) 180;
              default = 0;
              description = "Rotation of each lambda (in degrees)";
            };
            angle = lib.mkOption {
              type = mkIntTypeBetween (-180) 180;
              default = 30;
              description = "Lambda arm angle (in degrees)";
            };
            clipRadius = lib.mkOption {
              type = mkIntTypeBetween 0 300;
              default = 92;
              description = "Clipping n-gon radius (unknown units)";
            };
            clipRotation = lib.mkOption {
              type = mkIntTypeBetween (-180) 180;
              default = 0;
              description = "Clipping n-gon rotation (in degrees)";
            };
            clipInverse = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Reverse clipping order";
            };
            colors = lib.mkOption {
              type = lib.types.listOf lib.types.color;
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
        systems = nixpkgs.lib.platforms.linux;
        perSystem =
          {
            system,
            pkgs,
            lib,
            ...
          }:
          {
            _module.args.pkgs = import nixpkgs {
              inherit system;
              overlays = [ overlay ];
            };
            packages = {
              inherit (pkgs) openscad-unstable-fhs genix-to-image;
              testGenixFrame = pkgs.mkGenixFrame "test-genix-frame.png" { };
              testGenixPlymouthTheme = pkgs.mkGenixPlymouthTheme {
                name = "test-genix-plymouth-theme";
                animation = time: {
                  # Wait WTF nix doesn't have ANY common math stuff?!
                  lambdaThickness = builtins.floor (if time <= 1 then 20 + time * 10 else 20 + (2 - time) * 10);
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
              {
                config,
                pkgs,
                lib,
                ...
              }:
              {
                options = {
                  boot.plymouth.genix7000 = {
                    enable = lib.mkEnableOption "automatically generated genix7000 boot animations";
                    animation = lib.mkOption {
                      type = lib.types.functionTo mkGenixFrameArgsType;
                      example = ''
                        time: {
                          lambdaThickness = builtins.floor (if time <= 1 then 20 + time * 10 else 20 + (2 - time) * 10);
                          rotation = builtins.floor (if time <= 1 then time * 180 else (2 - time) * 180);
                        };
                      '';
                      description = "A function that takes the frame time and returns a set of parameters to pass to to-image";
                    };
                    defaults = lib.mkOption {
                      type = mkGenixFrameArgsType;
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
                        (pkgs.mkGenixPlymouthTheme {
                          name = "genix7000-autogenerated-theme";
                          animation = time: lib.recursiveUpdate cfg.defaults (cfg.animation time);
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
