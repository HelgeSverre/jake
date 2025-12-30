{
  description = "Jake - Modern command runner with Make's dependency tracking and Just's UX";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        version = "0.2.0";
      in
      {
        packages = {
          jake = pkgs.stdenv.mkDerivation {
            pname = "jake";
            inherit version;

            src = ../..;

            nativeBuildInputs = [ pkgs.zig ];

            dontConfigure = true;
            dontInstall = true;

            buildPhase = ''
              export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
              zig build -Doptimize=ReleaseSafe --prefix $out
            '';

            meta = with pkgs.lib; {
              description = "Modern command runner with Make's dependency tracking and Just's UX";
              homepage = "https://github.com/HelgeSverre/jake";
              license = licenses.mit;
              maintainers = [ ];
              platforms = platforms.unix;
              mainProgram = "jake";
            };
          };

          default = self.packages.${system}.jake;
        };

        apps = {
          jake = flake-utils.lib.mkApp {
            drv = self.packages.${system}.jake;
          };
          default = self.apps.${system}.jake;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
            zls # Zig Language Server
          ];

          shellHook = ''
            echo "Jake development environment"
            echo "Zig version: $(zig version)"
          '';
        };
      }
    );
}
