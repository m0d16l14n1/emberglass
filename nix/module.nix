{ config, lib, pkgs, ... }:

let
  cfg = config.services.emberglass;
in
{
  options.services.emberglass = {
    enable = lib.mkEnableOption "the emberglass sensor sampler and its panel widget";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "The emberglass package.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The CLI and the Plasma widget (share/plasma/plasmoids is on XDG_DATA_DIRS through the system profile).
    environment.systemPackages = [ cfg.package ];

    systemd.services.emberglass = {
      description = "emberglass sensor sampler (/run/emberglass, for panels and HUDs)";
      after = [ "sysinit.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 -I ${cfg.package}/lib/emberglass/emberglass-sampler";
        Restart = "on-failure";
        RestartSec = 5;
        Nice = 10;
        RuntimeDirectory = "emberglass";
        RuntimeDirectoryMode = "0755";
        RuntimeDirectoryPreserve = "yes";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = "AF_UNIX";
        MemoryMax = "64M";
      };
    };
  };
}
