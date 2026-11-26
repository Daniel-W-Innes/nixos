{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrByPath
    filterAttrs
    mapAttrs'
    mapAttrsToList
    mkMerge
    mkIf
    nameValuePair
    optionalString
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
          ${optionalString ns.openvpn.enable "${pkgs.nftables}/bin/nft delete table inet vpnc-host-${nsName} 2>/dev/null || true"}
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
          # Write every resolved remote to the .remote file so the tunnel
          # unit can fail over across the whole set (2026-11-25: a single
          # pinned endpoint can never recover from PIA retiring a server).
          : > /run/openvpn/${nsName}.remote
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
            echo "$ip4 $remote_port $remote_proto" >> /run/openvpn/${nsName}.remote
          done < <(${pkgs.gawk}/bin/awk '$1 == "remote" { print $2, $3, $4 }' "$cfg_file")
          [ -s /run/openvpn/${nsName}.remote ] || { echo "vpn-confinement: no remote directive in $cfg_file" >&2; exit 1; }

          # Host-side source NAT for the exemption path. The namespace's
          # only pre-tunnel egress carries the link-local veth address as
          # source, and upstream routers will not route replies back to a
          # link-local address — the TLS handshake blackholes without this
          # (2026-11-22: 60s TLS timeout, zero inbound packets). Postrouting
          # only sees forwarded traffic, so veth-local traffic (the
          # published RPC) is unaffected.
          ${pkgs.nftables}/bin/nft delete table inet vpnc-host-${nsName} 2>/dev/null || true
          ${pkgs.nftables}/bin/nft add table inet vpnc-host-${nsName}
          ${pkgs.nftables}/bin/nft 'add chain inet vpnc-host-${nsName} nat-postrouting { type nat hook postrouting priority srcnat; }'
          ${pkgs.nftables}/bin/nft add rule inet vpnc-host-${nsName} nat-postrouting ip saddr ${
            effectiveHostLink.${nsName}.nsAddressIPv4
          } masquerade
        ''}

        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.runtimeShell} -c ${lib.escapeShellArg policy.capture}

        success=1
      '';
      postStop = ''
        set -eu
        ${optionalString ns.openvpn.enable "${pkgs.nftables}/bin/nft delete table inet vpnc-host-${nsName} 2>/dev/null || true"}
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
          # Drop directives that fight the unit lifecycle: reconnect and
          # daemonization belong to systemd, auth is supplied explicitly
          # below, and privilege-dropping must not happen inside the
          # kill-switch namespace. ncp-disable is openvpn-2.4-era and
          # removed in 2.6 (PIA's .ovpn still ships it — parse error without
          # this).
          sed -E \
            -e '/^(ping|ping-exit|ping-restart|daemon|user|group|auth-user-pass|remote|up|down|ncp-disable)([[:space:]]|$)/d' \
            "${ns.openvpn.configFile}" > /run/openvpn/${nsName}.conf

          # The namespace unit resolved every `remote` of the .ovpn to a
          # literal IP at activation time (openvpn itself cannot resolve
          # before the tunnel exists) and wrote them to .remote. Append them
          # all: on connection failure — for UDP, defined by
          # --ping/--ping-restart — openvpn advances to the next remote, and
          # --connect-retry-max 0 cycles forever, so a retired server costs
          # minutes of failover instead of an outage (2026-11-25:
          # montreal429 was retired by PIA and a single pinned remote could
          # never recover). --remote-random spreads the initial pick across
          # the set.
          while read -r remote_ip remote_port remote_proto; do
            [ -n "$remote_ip" ] || continue
            echo "remote $remote_ip $remote_port $remote_proto" >> /run/openvpn/${nsName}.conf
          done < /run/openvpn/${nsName}.remote

          exec openvpn \
            --config "/run/openvpn/${nsName}.conf" \
            --remote-random \
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
          # "Tunnel usable" means more than an address on the interface:
          # redirect-gateway routes land a beat after the addr, and a
          # dependent that races them (pia-port-forward) picks a wrong
          # gateway (2026-11-22). Wait for both.
          for _ in $(seq 1 60); do
            if ip addr show dev "${ns.openvpn.interface}" 2>/dev/null | grep -q 'inet ' \
              && ip route show dev "${ns.openvpn.interface}" 2>/dev/null | grep -q ' via '; then
              # openvpn creates the --status file 0600, and the exporter
              # reads it as an unprivileged DynamicUser — without this
              # openvpn-exporter-down fires forever (it has since the
              # 2026-11-22 PIA move) and pia-tunnel-stalled has no input.
              # openvpn rewrites the same inode each 10 s cycle, so one
              # chmod per start holds, and the loop above guarantees the
              # file exists by now.
              chmod 0644 "${ns.openvpn.statusFile}"
              exit 0
            fi
            sleep 1
          done
          echo "vpn-confinement: openvpn interface ${ns.openvpn.interface} did not become usable in 60s" >&2
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

  # Watchdog: PIA rotates/retires servers behind its region hostnames. The
  # netns unit pins one resolved IP per `remote` at activation time, so
  # without this the tunnel can die permanently when a server disappears
  # (2026-11-25: montreal429 retired; openvpn's Restart=always loop can
  # never reconnect to a dead endpoint). When the status file goes stale
  # AND fresh resolution differs from the pinned set, restart the netns
  # unit: it re-resolves, re-punches the endpoint exemptions and reconnects
  # (transmission reloads — the price of a real rotation event). If the
  # resolution is unchanged the server is merely down; restarting would pin
  # the same dead IPs, so it does nothing. Literal-IP .ovpn configs always
  # compare equal, making the watchdog a no-op.
  openvpnWatchdog =
    nsName: ns:
    let
      script = pkgs.writeShellApplication {
        name = "vpn-confinement-openvpn-${nsName}-watchdog";
        runtimeInputs = with pkgs; [
          getent
          gawk
          coreutils
          systemd
        ];
        text = ''
          set -eu
          pinned=/run/openvpn/${nsName}.remote
          status=${ns.openvpn.statusFile}
          cfg=${ns.openvpn.configFile}

          # Only act when the tunnel is actually down: openvpn rewrites the
          # status file every 10 s, so a 5-minute-old mtime means the daemon
          # is wedged or endlessly reconnecting to a dead endpoint (the same
          # window as the pia-tunnel-stalled alert).
          [ -f "$pinned" ] || exit 0
          [ -f "$status" ] || exit 0
          now=$(date +%s)
          [ $(( now - $(stat -c %Y "$status") )) -ge 300 ] || exit 0

          # Re-resolve every remote of the .ovpn with host-side DNS (the
          # namespace resolves through the dead tunnel). Mirror the netns
          # unit's per-line proto defaulting so equal sets compare equal.
          proto=$(awk '$1 == "proto" { print $2; exit }' "$cfg")
          proto="''${proto:-udp}"
          fresh=$(
            while read -r host port line_proto; do
              [ -n "$host" ] || continue
              line_proto="''${line_proto:-$proto}"
              ip4=$(getent ahostsv4 "$host" | awk 'NR == 1 { print $1 }')
              [ -n "$ip4" ] || continue
              echo "$ip4 $port $line_proto"
            done < <(awk '$1 == "remote" { print $2, $3, $4 }' "$cfg")
          )
          [ -n "$fresh" ] || exit 0
          # All remotes must resolve — a partial resolution is a DNS
          # hiccup, and restarting the netns then would just fail its own
          # getent and tear the namespace down for nothing.
          [ "$(echo "$fresh" | wc -l)" = "$(wc -l < "$pinned")" ] || exit 0
          [ "$fresh" = "$(cat "$pinned")" ] && exit 0

          echo "vpn-confinement: ${nsName} endpoint set rotated (pinned: $(tr '\n' ';' < "$pinned") -> fresh: $(echo "$fresh" | tr '\n' ';')) — restarting netns to re-resolve and reconnect"
          systemctl restart "vpn-confinement-netns@${nsName}.service"
        '';
      };
    in
    {
      service = nameValuePair "vpn-confinement-openvpn-watchdog@${nsName}" {
        description = "Re-pin rotated OpenVPN endpoints in namespace ${nsName}";
        serviceConfig = helperUnitHardeningBase // {
          Type = "oneshot";
          ExecStart = "${script}/bin/vpn-confinement-openvpn-${nsName}-watchdog";
        };
      };
      timer = nameValuePair "vpn-confinement-openvpn-watchdog@${nsName}" {
        description = "Watch for rotated OpenVPN endpoints in namespace ${nsName}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10min";
          OnUnitActiveSec = "10min";
          AccuracySec = "1min";
        };
      };
    };

  openvpnWatchdogUnits =
    let
      pairs = mapAttrsToList (nsName: ns: openvpnWatchdog nsName ns) (
        filterAttrs (_: ns: ns.openvpn.enable) enabledNamespaces
      );
    in
    {
      services = builtins.listToAttrs (map (p: p.service) pairs);
      timers = builtins.listToAttrs (map (p: p.timer) pairs);
    };

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
        openvpnWatchdogUnits.services
      ];
      inherit (openvpnWatchdogUnits) timers;
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
