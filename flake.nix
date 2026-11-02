{
  description = "claude-cage confined to the project directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "claude-code" ];
            }
          )
        );

      color = {
        grey = "\\033[0;90m";
        gold = "\\033[38;5;220m";
        red = "\\033[0;31m";
        reset = "\\033[0m";
      };

      protected = [
        "flake.nix"
        "flake.lock"
        ".envrc"
        ".git/hooks"
        ".git/config"
      ];

      binPath =
        pkgs:
        lib.makeBinPath (
          with pkgs;
          [
            bashInteractive
            coreutils
            git
            ripgrep
            gnugrep
            gnused
            findutils
            gnutar
            gzip
          ]
        );

      mkClaude =
        pkgs:
        pkgs.writeShellApplication {
          name = "claude";
          runtimeInputs = [ pkgs.bubblewrap ];
          text = ''
            die() {
              printf '${color.red}claude-cage:${color.reset} %s\n' "$1" >&2
              exit 1
            }

            if [ -z "''${CLAUDE_CAGE_ROOT:-}" ]; then
              die "CLAUDE_CAGE_ROOT is not set (export it in the project's .envrc)"
            fi
            root="$CLAUDE_CAGE_ROOT"

            case "$PWD" in
              "$root"|"$root"/*) ;;
              *) die "current directory is outside the project root ($root)" ;;
            esac

            state="''${XDG_STATE_HOME:-$HOME/.local/state}/claude-cage"
            mkdir -p "$state"

            args=()
            for p in ${lib.concatStringsSep " " protected}; do
              if [ -e "$root/$p" ]; then
                args+=(--ro-bind "$root/$p" "$root/$p")
              fi
            done

            printf '${color.grey}claude-cage: confined to ${color.gold}%s${color.reset}\n' "$root" >&2

            exec bwrap \
              --unshare-all \
              --share-net \
              --die-with-parent \
              --new-session \
              --cap-drop ALL \
              --clearenv \
              --ro-bind /nix/store /nix/store \
              --ro-bind /etc/resolv.conf /etc/resolv.conf \
              --ro-bind /etc/hosts /etc/hosts \
              --ro-bind /etc/passwd /etc/passwd \
              --ro-bind /etc/group /etc/group \
              --proc /proc --dev /dev --tmpfs /tmp \
              --tmpfs /home/sandbox \
              --bind "$state" /claude-config \
              --bind "$root" "$root" \
              "''${args[@]}" \
              --chdir "$PWD" \
              --setenv HOME /home/sandbox \
              --setenv CLAUDE_CONFIG_DIR /claude-config \
              --setenv SHELL ${pkgs.bashInteractive}/bin/bash \
              --setenv PATH "${binPath pkgs}" \
              --setenv TERM "''${TERM:-xterm-256color}" \
              --setenv LANG C.UTF-8 \
              --setenv SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
              --setenv NODE_EXTRA_CA_CERTS ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
              --setenv DISABLE_AUTOUPDATER 1 \
              ${pkgs.claude-code}/bin/claude "$@"
          '';
        };
    in
    {
      packages = forAll (pkgs: {
        default = mkClaude pkgs;
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          name = "claude-cage";
          packages = [ (mkClaude pkgs) ];

          shellHook = ''
            # Project root = directory of the .envrc loading this shell
            export CLAUDE_CAGE_ROOT="$PWD"
            printf "\n${color.grey}claude-cage root: ${color.gold}%s${color.reset}\n" "$CLAUDE_CAGE_ROOT"
          '';
        };
      });
    };
}
