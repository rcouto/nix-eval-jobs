{
  description = "Hydra's builtin hydra-eval-jobs as a standalone";

  # Switch back after https://nixpk.gs/pr-tracker.html?pr=396710 is finished
  # inputs.nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";
  inputs.flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  inputs.nix-github-actions.url = "github:nix-community/nix-github-actions";
  inputs.nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    inputs@{ flake-parts, ... }:
    let
      inherit (inputs.nixpkgs) lib;
      inherit (inputs) self;
      nixVersion = lib.fileContents ./.nix-version;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-linux"
        "riscv64-linux"
        "x86_64-linux"

        "aarch64-darwin"
        "x86_64-darwin"
      ];
      imports = [ inputs.treefmt-nix.flakeModule ];

      flake.githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
        platforms = {
          "x86_64-linux" = [
            "nscloud-ubuntu-22.04-amd64-4x16-with-cache"
            "nscloud-cache-size-20gb"
            "nscloud-cache-tag-nix-eval-jobs"
          ];
          "x86_64-darwin" = "macos-13";
          "aarch64-darwin" = "macos-latest";
          "aarch64-linux" = [
            "nscloud-ubuntu-22.04-arm64-4x16-with-cache"
            "nscloud-cache-size-20gb"
            "nscloud-cache-tag-nix-eval-jobs"
          ];
        };

        checks = {
          inherit (self.checks) x86_64-linux aarch64-linux aarch64-darwin;
          x86_64-darwin = builtins.removeAttrs self.checks.x86_64-darwin [ "treefmt" ];
        };
      };

      perSystem =
        { pkgs, self', ... }:
        let
          drvArgs = {
            srcDir = self;
            nixComponents =
              if nixVersion == "latest" then
                pkgs.nixVersions.nix_latest
              else
                pkgs.nixVersions."nix_${nixVersion}";
          };
        in
        {
          treefmt.imports = [ ./dev/treefmt.nix ];
          packages.nix-eval-jobs = pkgs.callPackage ./default.nix drvArgs;
          packages.clangStdenv-nix-eval-jobs = pkgs.callPackage ./default.nix (
            drvArgs // { stdenv = pkgs.clangStdenv; }
          );
          packages.default = self'.packages.nix-eval-jobs;
          devShells.default = pkgs.callPackage ./shell.nix drvArgs;
          devShells.clang = pkgs.callPackage ./shell.nix (drvArgs // { stdenv = pkgs.clangStdenv; });

          checks = builtins.removeAttrs self'.packages [ "default" ] // {
            shell = self'.devShells.default;
            clang-tidy-fix = self'.packages.nix-eval-jobs.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [
                pkgs.git
                (lib.hiPrio pkgs.llvmPackages_latest.clang-tools)
              ];
              buildPhase = ''
                export HOME=$TMPDIR
                cat > $HOME/.gitconfig <<EOF
                [user]
                  name = Nix
                  email = nix@localhost
                [init]
                  defaultBranch = main
                EOF
                pushd ..
                git init
                git add .
                git commit -m init --quiet
                popd
                ninja clang-tidy-fix
                git status
                if ! git --no-pager diff --exit-code; then
                  echo "clang-tidy-fix failed, please run `ninja clang-tidy-fix` and commit the changes"
                  exit 1
                fi
              '';
              installPhase = ''
                touch $out
              '';
            });
          };
        };
    };
}
