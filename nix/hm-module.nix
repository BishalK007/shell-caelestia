self: {
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;

  cli-default = self.inputs.caelestia-cli.packages.${system}.default;
  shell-default = self.packages.${system}.with-cli;

  cfg = config.programs.caelestia;
in {
  imports = [
    (lib.mkRenamedOptionModule ["programs" "caelestia" "environment"] ["programs" "caelestia" "systemd" "environment"])
  ];
  options = with lib; {
    programs.caelestia = {
      enable = mkEnableOption "Enable Caelestia shell";
      package = mkOption {
        type = types.package;
        default = shell-default;
        description = "The package of Caelestia shell";
      };
      systemd = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the systemd service for Caelestia shell";
        };
        target = mkOption {
          type = types.str;
          description = ''
            The systemd target that will automatically start the Caelestia shell.
          '';
          default = config.wayland.systemd.target;
        };
        environment = mkOption {
          type = types.listOf types.str;
          description = "Extra Environment variables to pass to the Caelestia shell systemd service.";
          default = [];
          example = [
            "QT_QPA_PLATFORMTHEME=gtk3"
          ];
        };
      };
      settings = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = "Caelestia shell settings";
      };
      extraConfig = mkOption {
        type = types.str;
        default = "";
        description = "Caelestia shell extra configs written to shell.json";
      };
      cli = {
        enable = mkEnableOption "Enable Caelestia CLI";
        package = mkOption {
          type = types.package;
          default = cli-default;
          description = "The package of Caelestia CLI"; # Doesn't override the shell's CLI, only change from home.packages
        };
        settings = mkOption {
          type = types.attrsOf types.anything;
          default = {};
          description = "Caelestia CLI settings";
        };
        extraConfig = mkOption {
          type = types.str;
          default = "";
          description = "Caelestia CLI extra configs written to cli.json";
        };
      };
    };
  };

  config = let
    cli = cfg.cli.package;
    shell = cfg.package;
  in
    lib.mkIf cfg.enable {
      systemd.user.services.caelestia = lib.mkIf cfg.systemd.enable {
        Unit = {
          Description = "Caelestia Shell Service";
          After = [cfg.systemd.target];
          PartOf = [cfg.systemd.target];
          X-Restart-Triggers = lib.mkIf (cfg.settings != {}) [
            "${config.xdg.configFile."caelestia/shell.json".source}"
          ];
        };

        Service = {
          Type = "exec";
          # Kill stray UNMANAGED shell instances before starting the managed one.
          # Why: during development it's easy to launch the shell by hand (`caelestia
          # shell`, `qs -p ...`) and forget it. systemd only supervises the process in
          # THIS unit's cgroup, so on the next nixos-rebuild sd-switch restarts the
          # unit's instance while the manual one survives — two shells then coexist:
          # doubled bar/exclusive zones and a fight over caelestia:* global-shortcut
          # registrations (popups go dead). The stop phase of a restart has already
          # killed the unit's own process by the time ExecStartPre runs, so this only
          # ever matches strays. `-` prefix: pkill exits 1 when nothing matched, which
          # must not fail the unit. `-e` logs any kills to the journal for post-mortems.
          # The regex anchors on the binary path (/bin/quickshell or /bin/qs), so it
          # can't hit unrelated processes that merely mention quickshell in their args.
          ExecStartPre = "-${pkgs.procps}/bin/pkill -ef '/bin/(quickshell|qs)( |$)'";
          ExecStart = "${shell}/bin/caelestia-shell";
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStopSec = "5s";
          Environment =
            [
              "QT_QPA_PLATFORM=wayland"
            ]
            ++ cfg.systemd.environment;

          Slice = "session.slice";
        };

        Install = {
          WantedBy = [cfg.systemd.target];
        };
      };

      xdg.configFile = let
        mkConfig = c:
          lib.pipe (
            if c.extraConfig != ""
            then c.extraConfig
            else "{}"
          ) [
            builtins.fromJSON
            (lib.recursiveUpdate c.settings)
            builtins.toJSON
          ];
        shouldGenerate = c: c.extraConfig != "" || c.settings != {};
      in {
        "caelestia/shell.json" = lib.mkIf (shouldGenerate cfg) {
          text = mkConfig cfg;
        };
        "caelestia/cli.json" = lib.mkIf (shouldGenerate cfg.cli) {
          text = mkConfig cfg.cli;
        };
      };

      home.packages = [shell] ++ lib.optional cfg.cli.enable cli;
    };
}
