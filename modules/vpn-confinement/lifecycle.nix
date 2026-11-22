{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrByPath
    mapAttrs'
    mapAttrsToList
    mkMerge
    mkIf
    nameValuePair
    optionalString
    filterAttrs
    ;
  inherit (import ./context.nix { inherit config lib; })
    cfg
    vpnLib
    enabledNamespaces
    hostLinkEnabled
    effectiveHostLink
    namespacePath
    hostIfs
    nsIfs
    ;
  helperUnitHardeningBase = {
    NoNewPrivileges = true;
    LockPersonality = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    AmbientCapabilities = [ ];
  };

  namespaceUnitHardening = helperUnitHardeningBase // {
    CapabilityBoundingSet = [
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
  };

  endpointPinningUnitHardening = helperUnitHardeningBase // {
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
  };

  policies = import ./policy.nix { inherit lib pkgs; };

  namespaceUnits = mapAttrs' (
    nsName: ns:
    let
      withHostLink = hostLinkEnabled nsName ns;
      policy = policies.namespace nsName ns;
      unitName = "vpn-confinement-netns@${nsName}";
    in
    nameValuePair unitName {
      description = "Prepare VPN confinement namespace ${nsName}";
      # OpenVPN namespaces take the inverse dependency direction: the tunnel
      # unit is PartOf the namespace unit, so a namespace stop tears the
      # tunnel down first. WG namespaces keep the upstream direction.
      before = lib.optionals (!ns.openvpn.enable) [
        "wireguard-${ns.wireguard.interface}.service"
      ];
      partOf = lib.optionals (!ns.openvpn.enable) [
        "wireguard-${ns.wireguard.interface}.service"
      ];
      serviceConfig = namespaceUnitHardening // {
        RuntimeDirectory = policy.runtimeDirectory;
        RuntimeDirectoryMode = "0700";
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        cleanup_failed_start() {
          ${optionalString withHostLink "${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true"}
          ${pkgs.iproute2}/bin/ip netns del ${nsName} 2>/dev/null || true
        }

        success=0
        trap 'if [ "$success" -ne 1 ]; then cleanup_failed_start; fi' EXIT INT TERM

        ${pkgs.coreutils}/bin/mkdir -p /run/netns
        if [ ! -e ${namespacePath nsName} ]; then
          ${pkgs.iproute2}/bin/ip netns add ${nsName}
        fi

        ${pkgs.iproute2}/bin/ip -n ${nsName} link set lo up

        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft -f ${policy.file}

        ${optionalString withHostLink ''
          ${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true
          ${pkgs.iproute2}/bin/ip -n ${nsName} link del ${ns.hostLink.nsIf} 2>/dev/null || true

          ${pkgs.iproute2}/bin/ip link add ${ns.hostLink.hostIf} type veth peer name ${ns.hostLink.nsIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.hostLink.nsIf} netns ${nsName}
          ${pkgs.iproute2}/bin/ip addr replace ${
            effectiveHostLink.${nsName}.hostAddressIPv4
          }/30 dev ${ns.hostLink.hostIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.hostLink.hostIf} up
          ${pkgs.iproute2}/bin/ip -n ${nsName} addr replace ${
            effectiveHostLink.${nsName}.nsAddressIPv4
          }/30 dev ${ns.hostLink.nsIf}
          ${pkgs.iproute2}/bin/ip -n ${nsName} link set ${ns.hostLink.nsIf} up
        ''}

        ${optionalString (ns.ipv6.mode == "disable") ''
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        ''}

        ${optionalString ns.openvpn.enable ''
          # OpenVPN endpoint exemption. The tunnel daemon runs inside this
          # namespace, so before the tunnel exists it can only reach its
          # server through the hostLink veth. Parse the .ovpn config at
          # activation time, resolve every remote, and punch precise route +
          # nftables holes; all other traffic still dies at the drop policies.
          cfg_file="${ns.openvpn.configFile}"
          creds_file="${ns.openvpn.credentialsFile}"
          [ -f "$cfg_file" ] || { echo "vpn-confinement: openvpn config $cfg_file missing" >&2; exit 1; }
          [ -f "$creds_file" ] || { echo "vpn-confinement: openvpn credentials $creds_file missing" >&2; exit 1; }
          mkdir -p /run/openvpn

          proto="$(${pkgs.gawk}/bin/awk '$1 == "proto" { print $2; exit }' "$cfg_file")"
          proto="''${proto:-udp}"
          first=""
          while read -r remote_host remote_port remote_proto; do
            [ -n "$remote_host" ] || continue
            # pkgs.getent, not glibc.bin: nixpkgs moved getent out of the
            # glibc bin output (2026-11-22 outage — the build embeds the path
            # string without checking the file exists).
            ip4="$(${pkgs.getent}/bin/getent ahostsv4 "$remote_host" | ${pkgs.gawk}/bin/awk 'NR == 1 { print $1 }')"
            [ -n "$ip4" ] || { echo "vpn-confinement: could not resolve openvpn remote $remote_host" >&2; exit 1; }
            remote_proto="''${remote_proto:-$proto}"
            ${pkgs.iproute2}/bin/ip -n ${nsName} route add "$ip4/32" via ${
              effectiveHostLink.${nsName}.hostAddressIPv4
            }
            ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft add rule inet vpnc output oifname "${ns.hostLink.nsIf}" ip daddr "$ip4" "$remote_proto" dport "$remote_port" accept
            ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft add rule inet vpnc input iifname "${ns.hostLink.nsIf}" ip saddr "$ip4" accept
            [ -n "$first" ] || first="$ip4 $remote_port $remote_proto"
          done < <(${pkgs.gawk}/bin/awk '$1 == "remote" { print $2, $3, $4 }' "$cfg_file")
          [ -n "$first" ] || { echo "vpn-confinement: no remote directive in $cfg_file" >&2; exit 1; }
          echo "$first" > /run/openvpn/${nsName}.remote
        ''}

        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.runtimeShell} -c ${lib.escapeShellArg policy.capture}

        success=1
      '';
      postStop = ''
        set -eu
        ${optionalString withHostLink "${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true"}
        ${pkgs.iproute2}/bin/ip netns del ${nsName} 2>/dev/null || true
      '';
    }
  ) enabledNamespaces;

  wireguardNamespaces = filterAttrs (_: ns: !ns.openvpn.enable) enabledNamespaces;

  wireguardAssignments = mapAttrs' (
    nsName: ns:
    let
      endpointPinningMark =
        if ns.wireguard.endpointPinning.fwMark != null then
          ns.wireguard.endpointPinning.fwMark
        else
          vpnLib.deriveWireguardFwMark ns.wireguard.interface;
    in
    nameValuePair ns.wireguard.interface (
      {
        interfaceNamespace = lib.mkDefault nsName;
      }
      // lib.optionalAttrs (ns.wireguard.socketNamespace != null) {
        socketNamespace = lib.mkDefault ns.wireguard.socketNamespace;
      }
      // lib.optionalAttrs ns.wireguard.endpointPinning.enable {
        fwMark = lib.mkDefault (toString endpointPinningMark);
      }
    )
  ) wireguardNamespaces;

  wgDependencyUnits = mkMerge (
    mapAttrsToList (nsName: ns: {
      "wireguard-${ns.wireguard.interface}" = {
        after = [
          "vpn-confinement-netns@${nsName}.service"
        ]
        ++ lib.optionals ns.wireguard.endpointPinning.enable [
          "vpn-confinement-endpoint-pinning@${nsName}.service"
        ];
        requires = [
          "vpn-confinement-netns@${nsName}.service"
        ]
        ++ lib.optionals ns.wireguard.endpointPinning.enable [
          "vpn-confinement-endpoint-pinning@${nsName}.service"
        ];
        bindsTo = [
          "vpn-confinement-netns@${nsName}.service"
        ]
        ++ lib.optionals ns.wireguard.endpointPinning.enable [
          "vpn-confinement-endpoint-pinning@${nsName}.service"
        ];
      };
    }) wireguardNamespaces
  );

  openvpnUnits = mapAttrs' (
    nsName: ns:
    let
      runScript = pkgs.writeShellApplication {
        name = "vpn-confinement-openvpn-${nsName}-run";
        runtimeInputs = with pkgs; [
          openvpn
          coreutils
          gnused
        ];
        text = ''
          # The first remote of the .ovpn config, resolved to a literal IP by
          # the namespace unit (openvpn itself cannot resolve before the
          # tunnel exists). Extra remote lines get route + nftables
          # exemptions but are not tried for failover.
          read -r remote_ip remote_port remote_proto < /run/openvpn/${nsName}.remote

          # Drop directives that fight the unit lifecycle: reconnect and
          # daemonization belong to systemd, auth and remote are supplied
          # explicitly below, and privilege-dropping must not happen inside
          # the kill-switch namespace.
          sed -E \
            -e '/^(ping|ping-exit|ping-restart|daemon|user|group|auth-user-pass|remote|up|down)[[:space:]]/d' \
            "${ns.openvpn.configFile}" > /run/openvpn/${nsName}.conf

          exec openvpn \
            --config "/run/openvpn/${nsName}.conf" \
            --remote "$remote_ip" "$remote_port" "$remote_proto" \
            --auth-user-pass "${ns.openvpn.credentialsFile}" \
            --dev "${ns.openvpn.interface}" --dev-type tun \
            --status "${ns.openvpn.statusFile}" 10 \
            --writepid "/run/openvpn/${nsName}.pid" \
            --ping 10 --ping-restart 120 \
            --connect-retry 10 --connect-retry-max 0 \
            --resolv-retry infinite \
            --verb 3
        '';
      };
      waitScript = pkgs.writeShellApplication {
        name = "vpn-confinement-openvpn-${nsName}-wait";
        runtimeInputs = with pkgs; [
          iproute2
          gnugrep
          coreutils
        ];
        text = ''
          for _ in $(seq 1 60); do
            if ip addr show dev "${ns.openvpn.interface}" 2>/dev/null | grep -q 'inet '; then
              exit 0
            fi
            sleep 1
          done
          echo "vpn-confinement: openvpn interface ${ns.openvpn.interface} did not come up in 60s" >&2
          exit 1
        '';
      };
    in
    nameValuePair "vpn-confinement-openvpn@${nsName}" {
      description = "OpenVPN tunnel in confinement namespace ${nsName}";
      after = [ "vpn-confinement-netns@${nsName}.service" ];
      requires = [ "vpn-confinement-netns@${nsName}.service" ];
      bindsTo = [ "vpn-confinement-netns@${nsName}.service" ];
      partOf = [ "vpn-confinement-netns@${nsName}.service" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        TimeoutStartSec = 90;
        NetworkNamespacePath = namespacePath nsName;
        ExecStart = "${runScript}/bin/vpn-confinement-openvpn-${nsName}-run";
        ExecStartPost = "${waitScript}/bin/vpn-confinement-openvpn-${nsName}-wait";
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
        AmbientCapabilities = [ ];
        NoNewPrivileges = true;
        ProtectSystem = "full";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        # AF_NETLINK: openvpn installs the pushed routes itself.
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_NETLINK"
        ];
        SystemCallArchitectures = "native";
        UMask = "0022";
      };
    }
  ) (filterAttrs (_: ns: ns.openvpn.enable) enabledNamespaces);

  endpointPinningUnits =
    mapAttrs'
      (
        nsName: ns:
        let
          wg = ns.wireguard.interface;
          wgConfig = attrByPath [ wg ] null config.networking.wireguard.interfaces;
          policy = policies.endpoint nsName ns (if wgConfig == null then { } else wgConfig);
          socketBirthplace =
            if ns.wireguard.socketNamespace == null || ns.wireguard.socketNamespace == "init" then
              "init"
            else
              ns.wireguard.socketNamespace;
          nftExec = "${pkgs.nftables}/bin/nft";
          tableName = policy.table;
          birthplaceManaged =
            socketBirthplace != "init" && builtins.hasAttr socketBirthplace enabledNamespaces;
          unitName = "vpn-confinement-endpoint-pinning@${nsName}";
        in
        nameValuePair unitName {
          description = "Apply endpoint pinning policy for ${wg}";
          before = [ "wireguard-${wg}.service" ];
          after = lib.optionals birthplaceManaged [ "vpn-confinement-netns@${socketBirthplace}.service" ];
          requires = lib.optionals birthplaceManaged [ "vpn-confinement-netns@${socketBirthplace}.service" ];
          bindsTo = lib.optionals birthplaceManaged [ "vpn-confinement-netns@${socketBirthplace}.service" ];
          partOf = [ "wireguard-${wg}.service" ];
          serviceConfig =
            endpointPinningUnitHardening
            // lib.optionalAttrs (socketBirthplace != "init") {
              NetworkNamespacePath = namespacePath socketBirthplace;
            }
            // {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = policy.runtimeDirectory;
              RuntimeDirectoryMode = "0700";
            };
          script = ''
            set -eu
            ${nftExec} -f ${policy.file}
            ${policy.capture}
          '';
          postStop = ''
            set -eu
            ${nftExec} delete table inet ${tableName} >/dev/null 2>&1 || true
          '';
        }
      )
      (filterAttrs (_: ns: !ns.openvpn.enable && ns.wireguard.endpointPinning.enable) enabledNamespaces);

in
{
  config = mkIf cfg.enable {
    systemd = {
      tmpfiles.rules = [
        "d /run/openvpn 0755 root root -"
      ];
      services = mkMerge [
        namespaceUnits
        endpointPinningUnits
        wgDependencyUnits
        openvpnUnits
      ];
      network.networks = lib.listToAttrs (
        map (name: {
          name = "09-vpn-confinement-${name}";
          value = {
            matchConfig.Name = name;
            linkConfig.Unmanaged = true;
          };
        }) (hostIfs ++ nsIfs)
      );
    };
    networking = {
      wireguard.interfaces = wireguardAssignments;
      # These veths have module-owned static addresses. Host managers must not
      # add DHCP, IPv4LL or router-discovery configuration to them.
      dhcpcd.denyInterfaces = hostIfs ++ nsIfs;
      networkmanager.unmanaged = map (name: "interface-name:${name}") (hostIfs ++ nsIfs);
    };
  };
}
