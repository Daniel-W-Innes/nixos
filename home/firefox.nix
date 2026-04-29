{ pkgs, ... }:
let
  mkFirefoxExtension =
    {
      pname,
      version,
      addonId,
      url,
      hash,
      permissions,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version;
      src = pkgs.fetchurl {
        inherit url hash;
      };
      dontUnpack = true;
      installPhase = ''
        install -Dm444 "$src" "$out/share/mozilla/extensions/${addonId}.xpi"
      '';
      passthru = {
        inherit addonId;
        inherit permissions;
      };
      meta = {
        mozPermissions = permissions;
      };
    };

  bitwarden = mkFirefoxExtension {
    pname = "bitwarden-password-manager";
    version = "2026.3.0";
    addonId = "{446900e4-71c2-419f-a6a7-df9c091e268b}";
    url = "https://addons.mozilla.org/firefox/downloads/file/4749958/bitwarden_password_manager-2026.3.0.xpi";
    hash = "sha256-LcbQdNTcCr0qiWb1BlpV5yUrv15Usjwx2+2r+sDU28Q=";
    permissions = [
      "*://*/*"
      "<all_urls>"
      "alarms"
      "clipboardRead"
      "clipboardWrite"
      "contextMenus"
      "file:///*"
      "idle"
      "nativeMessaging"
      "notifications"
      "storage"
      "tabs"
      "unlimitedStorage"
      "webNavigation"
      "webRequest"
      "webRequestBlocking"
    ];
  };

  dnssec = mkFirefoxExtension {
    pname = "dnssec";
    version = "1.1.1resigned1";
    addonId = "{70b4fb8a-ae41-4e66-99f5-0fa89e411d69}";
    url = "https://addons.mozilla.org/firefox/downloads/file/4273645/dnssec-1.1.1resigned1.xpi";
    hash = "sha256-br0bfu3/nxjdFBU7l4U9r2OZ18xnmBFYoya34c06oaQ=";
    permissions = [
      "<all_urls>"
      "storage"
      "tabs"
      "webNavigation"
      "webRequest"
    ];
  };

  harper = mkFirefoxExtension {
    pname = "private-grammar-checker-harper";
    version = "2.1.0";
    addonId = "harper@writewithharper.com";
    url = "https://addons.mozilla.org/firefox/downloads/file/4778851/private_grammar_checker_harper-2.1.0.xpi";
    hash = "sha256-caNvUid/kE6Lpv5ePEuPHJQE+zUBN4Het6uHTe8izgE=";
    permissions = [
      "<all_urls>"
      "https://docs.google.com/document/*"
      "https://writewithharper.com/*"
      "storage"
      "tabs"
    ];
  };

  singleFile = mkFirefoxExtension {
    pname = "single-file";
    version = "1.22.98";
    addonId = "{531906d3-e22f-4a6c-a102-8057b88a1a63}";
    url = "https://addons.mozilla.org/firefox/downloads/file/4704412/single_file-1.22.98.xpi";
    hash = "sha256-9BdNiqQzVPRfJ1Mm4BA2YP7oEhwlpDvoTXoFrIVu888=";
    permissions = [
      "<all_urls>"
      "bookmarks"
      "clipboardWrite"
      "downloads"
      "identity"
      "menus"
      "nativeMessaging"
      "storage"
      "tabs"
      "webRequest"
      "webRequestBlocking"
    ];
  };

  readAloud = mkFirefoxExtension {
    pname = "read-aloud";
    version = "1.81.1";
    addonId = "{ddc62400-f22d-4dd3-8b4a-05837de53c2e}";
    url = "https://addons.mozilla.org/firefox/downloads/file/4687318/read_aloud-1.81.1.xpi";
    hash = "sha256-AOa62piBQQj6o84QggO1BS2463FKJ0chpLUy9w+hVFg=";
    permissions = [
      "activeTab"
      "file://*/*"
      "http://*/"
      "https://*/"
      "https://piper.ttstool.com/"
      "https://supertonic.ttstool.com/"
      "https://translate.google.com/"
      "identity"
      "menus"
      "storage"
      "webNavigation"
      "webRequest"
      "webRequestBlocking"
    ];
  };

  facebookContainer = mkFirefoxExtension {
    pname = "facebook-container";
    version = "2.3.12";
    addonId = "@contain-facebook";
    url = "https://addons.mozilla.org/firefox/downloads/file/4451874/facebook_container-2.3.12.xpi";
    hash = "sha256-M2m9hlh3hg5tfTg5nVkCswDT1XN6yy0TQv9b6x03gME=";
    permissions = [
      "<all_urls>"
      "browsingData"
      "contextualIdentities"
      "cookies"
      "management"
      "storage"
      "tabs"
      "webRequest"
      "webRequestBlocking"
    ];
  };

  enhancerForYouTube = mkFirefoxExtension {
    pname = "enhancer-for-youtube";
    version = "2.0.133.1";
    addonId = "enhancerforyoutube@maximerf.addons.mozilla.org";
    url = "https://addons.mozilla.org/firefox/downloads/file/4756023/enhancer_for_youtube-2.0.133.1.xpi";
    hash = "sha256-ieIJq4NR/4C5B3NV2oOp0qN60Sq2enL1JGKSSke8Wuw=";
    permissions = [
      "*://www.youtube.com/*"
      "*://www.youtube.com/embed/*"
      "*://www.youtube.com/live_chat*"
      "*://www.youtube.com/shorts/*"
      "storage"
    ];
  };

  duckDuckGoPrivacyEssentials = mkFirefoxExtension {
    pname = "duckduckgo-for-firefox";
    version = "2026.1.12";
    addonId = "jid1-ZAdIEUB7XOzOJw@jetpack";
    url = "https://addons.mozilla.org/firefox/downloads/file/4663303/duckduckgo_for_firefox-2026.1.12.xpi";
    hash = "sha256-r+wLhxCNrtOgAXqKHVSFwZawoaJ4MdyF1TtnQAs55Vs=";
    permissions = [
      "*://*/*"
      "<all_urls>"
      "activeTab"
      "alarms"
      "contextMenus"
      "storage"
      "tabs"
      "webNavigation"
      "webRequest"
      "webRequestBlocking"
    ];
  };

  simpleLogin = mkFirefoxExtension {
    pname = "simplelogin";
    version = "3.0.7";
    addonId = "addon@simplelogin";
    url = "https://addons.mozilla.org/firefox/downloads/file/4458602/simplelogin-3.0.7.xpi";
    hash = "sha256-jpHQt+K8dnRoGN2MxTPqUlucPP1DP7pS2kdmqD9Xne0=";
    permissions = [
      "activeTab"
      "contextMenus"
      "http://*/*"
      "https://*.simplelogin.io/*"
      "https://*/*"
      "scripting"
      "storage"
      "tabs"
    ];
  };
in
{
  programs.firefox = {
    enable = true;
    profiles.main = {
      isDefault = true;
      bookmarks = {
        force = true;
        settings = [
          {
            name = "toolbar";
            toolbar = true;
            bookmarks = [
              {
                name = "Chess";
                bookmarks = [
                  {
                    name = "chess.com";
                    url = "https://www.chess.com/";
                  }
                  {
                    name = "OpeningTree";
                    url = "https://www.openingtree.com/";
                  }
                  {
                    name = "Rosen Score";
                    url = "https://rosenscore.com/";
                  }
                ];
              }
              {
                name = "TTRPG";
                bookmarks = [
                  {
                    name = " SKiM anydice";
                    url = "https://anydice.com/program/3817a";
                  }
                  {
                    name = "Dice Calculator";
                    url = "https://dice.clockworkmod.com/#";
                  }
                  {
                    name = "Medieval Fantasy City Generator by watabou";
                    url = "https://watabou.itch.io/medieval-fantasy-city-generator";
                  }
                  {
                    name = "Reroll";
                    url = "https://app.reroll.co/select-character";
                  }
                  {
                    name = "City Generator";
                    url = "http://oskarstalberg.com/game/CityGenerator/";
                  }
                  {
                    name = "D&D Compendium - Maps & Map Tools";
                    url = "https://www.dnd-compendium.com/dm-resources/maps-map-tools";
                  }
                  {
                    name = "donjon; RPG Tools";
                    url = "https://donjon.bin.sh/";
                  }
                  {
                    name = "Azgaar's Fantasy Map Generator v1.4";
                    url = "https://azgaar.github.io/Fantasy-Map-Generator/";
                  }
                  {
                    name = "Shadow Sorcerer Guide D&D 5e - YouTube";
                    url = "https://www.youtube.com/watch?v=TlBsefiyVq0";
                  }
                  {
                    name = "Hero Forge Custom Miniatures";
                    url = "https://www.heroforge.com/";
                  }
                  {
                    name = "felddy/foundryvtt-docker: An easy-to-deploy Dockerized Foundry Virtual Tabletop server.";
                    url = "https://github.com/felddy/foundryvtt-docker";
                  }
                  {
                    name = "Send This To Your New Dungeon Master - YouTube";
                    url = "https://www.youtube.com/watch?v=fzgrTgorEFU";
                  }
                  {
                    name = "DnD";
                    bookmarks = [
                      {
                        name = "Sorlock (5e Optimized Character Build) - D&D Wiki";
                        url = "https://www.dandwiki.com/wiki/Sorlock_(5e_Optimized_Character_Build)";
                      }
                      {
                        name = "RPGBOT - Analysis, tools, and instructional articles for tabletop RPGs";
                        url = "https://rpgbot.net/";
                      }
                      {
                        name = "Brendan";
                        bookmarks = [
                          {
                            name = "Monk Druid Multiclass — SkullSplitter Dice";
                            url = "https://www.skullsplitterdice.com/blogs/dnd/monk-druid-multiclass";
                          }
                          {
                            name = "Fungal Fury: Stacking Up Damage with the Spores Druid | D&D 5e Build - YouTube";
                            url = "https://www.youtube.com/watch?v=KjmJKlhvCOY";
                          }
                          {
                            name = "Wild Shape: A Practical Guide - DnD 5e - RPGBOT";
                            url = "https://rpgbot.net/dnd5/characters/classes/druid/wild-shape/";
                          }
                          {
                            name = "Druid 5e: DnD 5th Edition Class Guide - RPGBOT";
                            url = "https://rpgbot.net/dnd5/characters/classes/druid/";
                          }
                        ];
                      }
                      {
                        name = "D&D 5e quick reference";
                        url = "http://crobi.github.io/dnd5e-quickref/preview/quickref.html";
                      }
                      {
                        name = "Vicky - D&D Beyond";
                        url = "https://www.dndbeyond.com/profile/BrotherWolf88/characters/7641832";
                      }
                      {
                        name = "5e Class Tier List (a bit more in-depth) - Tips & Tactics - Dungeons & Dragons Discussion - D&D Beyond Forums - D&D Beyond";
                        url = "https://www.dndbeyond.com/forums/dungeons-dragons-discussion/tips-tactics/7108-5e-class-tier-list-a-bit-more-in-depth";
                      }
                      {
                        name = "The 48 Laws of Power: Law 24: Play the Perfect Courtier";
                        url = "https://48laws-of-power.blogspot.com/2011/05/law-24-play-perfect-courtier.html";
                      }
                      {
                        name = "These Dungeons and Dragons 5e Rules as Written Are Dumb - YouTube";
                        url = "https://www.youtube.com/watch?v=PQDYZUwEyEs&list=UUly0Thn_yZouwdJtg7Am62A&index=4";
                      }
                      {
                        name = "Top 5 Dungeons and Dragons 5e Rules Everyone Gets Wrong - YouTube";
                        url = "https://www.youtube.com/watch?v=tYUG7FBJC94";
                      }
                      {
                        name = "dnd 5e - Does Repelling Blast work once per spell or once per beam? - Role-playing Games Stack Exchange";
                        url = "https://rpg.stackexchange.com/questions/88025/does-repelling-blast-work-once-per-spell-or-once-per-beam";
                      }
                      {
                        name = "Character Builder » Dungeons & Dragons - D&D 5";
                        url = "https://www.aidedd.org/dnd-builder/index.php";
                      }
                      {
                        name = "D&D Sage Advice · Questions on Dungeons & Dragons answered by game designers %";
                        url = "https://www.sageadvice.eu/";
                      }
                    ];
                  }
                  {
                    name = "Numenera";
                    bookmarks = [
                      {
                        name = "Numenera Character Generator";
                        url = "https://numenera-chargen.inocencio.dev/";
                      }
                      {
                        name = "Numenera Deep Dive - Experiences and Tips for D&D DMs #numenera #lazydm - YouTube";
                        url = "https://www.youtube.com/watch?v=QUyyVU4IUV8";
                      }
                    ];
                  }
                  {
                    name = "starfinder";
                    bookmarks = [
                      {
                        name = "▷ Random Spaceship Generator | Rolegenerator";
                        url = "https://www.rolegenerator.com/en/module/spaceship";
                      }
                      {
                        name = "StephaneDoiron.com";
                        url = "https://www.stephanedoiron.com/rpgs/starfinder/encounter_calculator/";
                      }
                      {
                        name = "Home // Starfinder Ship Encounter Generator";
                        url = "https://acejon.co.uk/starfinder/";
                      }
                      {
                        name = "How It's Played: Starfinder - YouTube";
                        url = "https://www.youtube.com/playlist?list=PLYCDCUfG0xJaiOsB99j8H3wyI8gGbxPuP";
                      }
                    ];
                  }
                  {
                    name = "Torus";
                    bookmarks = [
                      {
                        name = "If Planets Were Donuts - YouTube";
                        url = "https://www.youtube.com/watch?v=1J4iIBKJHLA";
                      }
                      {
                        name = "Donut-Shaped Planets - Sixty Symbols - YouTube";
                        url = "https://www.youtube.com/watch?v=fMlGs4X67q8";
                      }
                      {
                        name = "irigi bloguje: Toroidal World";
                        url = "https://irigi.blogspot.com/2010/11/toroidal-world.html";
                      }
                      {
                        name = "evolution - What would the problems with / consequences of a torus shaped planet be? - Worldbuilding Stack Exchange";
                        url = "https://worldbuilding.stackexchange.com/questions/6465/what-would-the-problems-with-consequences-of-a-torus-shaped-planet-be";
                      }
                      {
                        name = "Andart: Torus-Earth";
                        url = "https://www.aleph.se/andart/archives/2014/02/torusearth.html";
                      }
                      {
                        name = "Andart: More donuts, with warm filling";
                        url = "https://www.aleph.se/andart/archives/2014/02/more_donuts_with_warm_filling.html";
                      }
                      {
                        name = "Donut-Shaped Planets - Sixty Symbols - YouTube";
                        url = "https://www.youtube.com/watch?v=fMlGs4X67q8";
                      }
                    ];
                  }
                  {
                    name = "Gortle's Spell Guide for the Sorcerer PF2 Remastered";
                    url = "https://docs.google.com/document/d/e/2PACX-1vTM1aBK2R2JYUHGie7C93kbODLO6nh79no8QQj4tgGLfXIqNYOaFQAKjXKTCL0RKO8MscnBRPbEPLjZ/pub";
                  }
                  {
                    name = "Checkout - KakapopoTCG";
                    url = "https://www.kakapopotcg.com/checkouts/cn/Z2NwLWV1cm9wZS13ZXN0NDowMUpORVpXMU1UNVRHQzdZNE1DMEtSMURBQQ?auto_redirect=false&discount=Volume-Discount+1-%5Bbg67s6f%5D&edge_redirect=true&locale=en&skip_shop_pay=true";
                  }
                ];
              }
              {
                name = "English";
                bookmarks = [
                  {
                    name = "Hemingway Editor";
                    url = "http://www.hemingwayapp.com/";
                  }
                  {
                    name = "Note-taking In Ford Improved Shorthand | by Abby Starnes | Medium";
                    url = "https://medium.com/@abbymstarnes/note-taking-in-ford-improved-shorthand-34a2736ff8a9";
                  }
                  {
                    name = "Duolingo - The world's best way to learn Latin";
                    url = "https://www.duolingo.com/learn";
                  }
                  {
                    name = "latintutorial - YouTube";
                    url = "https://www.youtube.com/c/latintutorial";
                  }
                  {
                    name = "Latin's Case System - YouTube";
                    url = "https://www.youtube.com/watch?v=2fhP_fk2wNQ";
                  }
                ];
              }
              {
                name = "Math";
                bookmarks = [
                  {
                    name = "Desmos";
                    url = "https://www.desmos.com/calculator";
                  }
                  {
                    name = "3D Graph using Parametric Lines";
                    url = "https://www.desmos.com/calculator/nqom2ih05g";
                  }
                  {
                    name = "Discrete Mathematics Study Center";
                    url = "http://cglab.ca/~discmath/exercises.html";
                  }
                  {
                    name = "Set symbols of set theory (Ø,U,{},∈,...)";
                    url = "https://www.rapidtables.com/math/symbols/Set_Symbols.html";
                  }
                  {
                    name = "Z-Scores and Normal Distribution";
                    url = "https://www.desmos.com/calculator/uugyzl6q8x";
                  }
                  {
                    name = "Binomial distributions | Probabilities of probabilities, part 1 - YouTube";
                    url = "https://www.youtube.com/watch?v=8idr1WZ1A7Q";
                  }
                ];
              }
              {
                name = "Programming";
                bookmarks = [
                  {
                    name = "CUE";
                    url = "https://cuelang.org/";
                  }
                  {
                    name = "Jsonnet - The Data Templating Language";
                    url = "https://jsonnet.org/";
                  }
                  {
                    name = "Architectural Katas: Practicing Architecture";
                    url = "http://www.architecturalkatas.com/index.html";
                  }
                  {
                    name = "ngrok - Online in One Line";
                    url = "https://ngrok.com/";
                  }
                  {
                    name = "Convert cURL command syntax to Python requests, Node.js, R, PHP, Strest, Go, JSON, and Rust code";
                    url = "https://curl.trillworks.com/";
                  }
                  {
                    name = "TensorFlow";
                    url = "https://www.tensorflow.org/";
                  }
                  {
                    name = "Prerequisites and Prework | Machine Learning Crash Course | Google Developers";
                    url = "https://developers.google.com/machine-learning/crash-course/prereqs-and-prework";
                  }
                  {
                    name = "How to delete a node from Binary Search Tree (BST)? - Java Interview Programs";
                    url = "http://www.java2novice.com/java-interview-programs/delete-node-binary-search-tree-bst/";
                  }
                  {
                    name = "Racket Cheat Sheet";
                    url = "https://docs.racket-lang.org/racket-cheat/index.html";
                  }
                  {
                    name = "AAkira/Kotlin-Multiplatform-Libraries: Kotlin Multiplatform Libraries. Welcome PR if you find or create new Kotlin Multiplatform Library.";
                    url = "https://github.com/AAkira/Kotlin-Multiplatform-Libraries";
                  }
                  {
                    name = "Information - ZSA Technology Labs - Checkout";
                    url = "https://checkout.zsa.io/31108497545/checkouts/00e8f8dd57bf5172b6b8a8dc4e974445";
                  }
                  {
                    name = "Netlify: All-in-one platform for automating modern web projects";
                    url = "https://www.netlify.com/";
                  }
                  {
                    name = "For fast and secure sites | Jamstack";
                    url = "https://jamstack.org/";
                  }
                  {
                    name = "JohnHammond/katana: Katana - Automatic CTF Challenge Solver in Python3";
                    url = "https://github.com/JohnHammond/katana";
                  }
                  {
                    name = "Keylength - Compare all Methods";
                    url = "https://www.keylength.com/en/compare/";
                  }
                  {
                    name = "Brendon Matheson - A Step-by-Step Guide to Connecting Prometheus to pfSense via SNMP";
                    url = "https://brendonmatheson.com/2021/02/07/step-by-step-guide-to-connecting-prometheus-to-pfsense-via-snmp.html";
                  }
                  {
                    name = "Tiling in KDE Plasma - Bismuth First Look - YouTube";
                    url = "https://www.youtube.com/watch?v=rYG4QU0miNQ";
                  }
                  {
                    name = "edgard/iperf3_exporter: Simple server that probes iPerf3 endpoints and exports results via HTTP for Prometheus consumption";
                    url = "https://github.com/edgard/iperf3_exporter";
                  }
                  {
                    name = "Awesome Prometheus alerts | Collection of alerting rules";
                    url = "https://awesome-prometheus-alerts.grep.to/rules#openebs";
                  }
                  {
                    name = "EAP-TLS";
                    bookmarks = [
                      {
                        name = "802.1X EAP-TLS Authentication Flow Explained";
                        url = "https://www.securew2.com/blog/802-1x-eap-tls-authentication-flow-explained";
                      }
                      {
                        name = "4-Way Handshake - WiFi";
                        url = "https://www.wifi-professionals.com/2019/01/4-way-handshake";
                      }
                    ];
                  }
                  {
                    name = "SDR";
                    bookmarks = [
                      {
                        name = "Power amplifier for hackrf one or other SDR. : RTLSDR";
                        url = "https://www.reddit.com/r/RTLSDR/comments/ecfizc/power_amplifier_for_hackrf_one_or_other_sdr/";
                      }
                      {
                        name = "HackRF One - Great Scott Gadgets";
                        url = "https://greatscottgadgets.com/hackrf/one/";
                      }
                    ];
                  }
                  {
                    name = "HA K8s";
                    bookmarks = [
                      {
                        name = "Creating Highly Available clusters with kubeadm | Kubernetes";
                        url = "https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/";
                      }
                      {
                        name = "Using CoreDNS for Service Discovery | Kubernetes";
                        url = "https://kubernetes.io/docs/tasks/administer-cluster/coredns/";
                      }
                      {
                        name = "Kubernetes - Traefik";
                        url = "https://docs.traefik.io/v1.7/user-guide/kubernetes/";
                      }
                      {
                        name = "IBM/ansible-kubernetes-ha-cluster: This repository provides Ansible Playbooks To setup Kubernetes HA on Redhat Enterprise Linux 7. The playbooks are mainly inspired by Kubeadm documentation and other ansible tentatives on github. The playbooks could be used separately or as one playbook for a fully fledged HA cluster.";
                        url = "https://github.com/IBM/ansible-kubernetes-ha-cluster";
                      }
                    ];
                  }
                  {
                    name = "Passwords";
                    bookmarks = [
                      {
                        name = "Security Issue: Combining Bcrypt With Other Hash Functions | ircmaxell's Blog";
                        url = "https://blog.ircmaxell.com/2015/03/security-issue-combining-bcrypt-with.html";
                      }
                      {
                        name = "Password Storage - OWASP Cheat Sheet Series";
                        url = "https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#work-factors";
                      }
                      {
                        name = "Hashing in Action: Understanding bcrypt";
                        url = "https://auth0.com/blog/hashing-in-action-understanding-bcrypt/";
                      }
                      {
                        name = "hash - What is the specific reason to prefer bcrypt or PBKDF2 over SHA256-crypt in password hashes? - Information Security Stack Exchange";
                        url = "https://security.stackexchange.com/questions/133239/what-is-the-specific-reason-to-prefer-bcrypt-or-pbkdf2-over-sha256-crypt-in-pass";
                      }
                      {
                        name = "passwords - How to apply a pepper correctly to bcrypt? - Information Security Stack Exchange";
                        url = "https://security.stackexchange.com/questions/21263/how-to-apply-a-pepper-correctly-to-bcrypt";
                      }
                      {
                        name = "Generating a SHA256 HMAC Hash · GolangCode";
                        url = "https://golangcode.com/generate-sha256-hmac/";
                      }
                    ];
                  }
                  {
                    name = "Linux";
                    bookmarks = [
                      {
                        name = "dm-crypt/Encrypting an entire system - ArchWiki";
                        url = "https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#Btrfs_subvolumes_with_swap";
                      }
                    ];
                  }
                  {
                    name = "Open-source load testing tool for developers | k6 OSS";
                    url = "https://k6.io/open-source";
                  }
                  {
                    name = "Boolean Algebra Calculator - Online Boole Logic Expression Simplifier";
                    url = "https://www.dcode.fr/boolean-expressions-calculator";
                  }
                  {
                    name = "My NeoVim Go(lang) setup — As good as Intellj/Goland IDE | by Suyash Raj | Medium";
                    url = "https://medium.com/@suyash10581108/my-neovim-go-lang-setup-as-good-as-intellj-goland-ide-d48dd765f6de";
                  }
                ];
              }
              {
                name = "Random";
                bookmarks = [
                  {
                    name = "The Eye | Front Page";
                    url = "http://the-eye.eu/";
                  }
                  {
                    name = "Unscramble YAK | 6 Words With the Letters YAK";
                    url = "https://wordfinder.yourdictionary.com/unscramble/yak/";
                  }
                  {
                    name = "MRS_STATRPT_2017 V4.PDF";
                    url = "https://media.defense.gov/2018/Jul/30/2001948113/-1/-1/0/MRS_STATRPT_2017%20V4.PDF";
                  }
                  {
                    name = "Average ages per rank in US Military | Transformers Universe MUX | FANDOM powered by Wikia";
                    url = "https://tfumux.fandom.com/wiki/Average_ages_per_rank_in_US_Military";
                  }
                  {
                    name = "Top 20 Free Digital Forensic Investigation Tools for SysAdmins";
                    url = "https://techtalk.gfi.com/top-20-free-digital-forensic-investigation-tools-for-sysadmins/";
                  }
                  {
                    name = "The Photographer's Ephemeris - Web App";
                    url = "https://app.photoephemeris.com/?ll=45.427864,-75.694912&center=45.4248,-75.6907&z=13&spn=0.06,0.14&dt=20180205194500-0500&sll=45.635917,-76.054898";
                  }
                  {
                    name = "Free vs Pro • DisplayFusion by Binary Fortress Software";
                    url = "https://www.displayfusion.com/Compare/";
                  }
                  {
                    name = "Applications | WhatPulse Dashboard";
                    url = "https://whatpulse.org/dashboard/my/applications";
                  }
                  {
                    name = "Circuit Simulator Applet";
                    url = "http://www.falstad.com/circuit/";
                  }
                  {
                    name = "FASCISM: An In-Depth Explanation - YouTube";
                    url = "https://www.youtube.com/watch?v=1T_98uT1IZs";
                  }
                  {
                    name = "Gestures for public speaking - the beginners' guide to scholars' cradles - YouTube";
                    url = "https://www.youtube.com/watch?v=gpqfZJuZRNY";
                  }
                  {
                    name = "How to make a Custom VRChat Avatar QUICK EASY and FREE - YouTube";
                    url = "https://www.youtube.com/watch?v=NT-zi7_F3Pc";
                  }
                  {
                    name = "Snow Plow Route Optimization : gis";
                    url = "https://www.reddit.com/r/gis/comments/2w4gru/snow_plow_route_optimization/cos0u0k/";
                  }
                  {
                    name = "The Biggest Myth In Education - YouTube";
                    url = "https://www.youtube.com/watch?v=rhgwIhB58PA";
                  }
                  {
                    name = "Why “No Problem” Can Seem Rude: Phatic Expressions - YouTube";
                    url = "https://www.youtube.com/watch?v=eGnH0KAXhCw";
                  }
                  {
                    name = "Woolie's Item & Equipment Tier List (Please leave a comment for feedback. Thank you!) - Google Sheets";
                    url = "https://docs.google.com/spreadsheets/d/1C3EJGoAWrjsgDs1lIpXUjq-qKul1f-oC1LeEcanAde0/edit#gid=682224160";
                  }
                  {
                    name = "[Qtile] Nord Qtile : unixporn";
                    url = "https://www.reddit.com/r/unixporn/comments/ecb16y/qtile_nord_qtile/";
                  }
                  {
                    name = "Create a map | Mapcustomizer.com";
                    url = "https://www.mapcustomizer.com/";
                  }
                  {
                    name = "Choosing a New Bishop | Yes, Prime Minister | BBC Comedy Greats - YouTube";
                    url = "https://www.youtube.com/watch?v=m2dNCw0hPLs";
                  }
                  {
                    name = "Vaccines: A Measured Response - YouTube";
                    url = "https://www.youtube.com/watch?v=8BIcAZxFfrc";
                  }
                  {
                    name = "Wilson-Raybould details pressure, 'veiled threats' over SNC-Lavalin affair - YouTube";
                    url = "https://www.youtube.com/watch?v=z3RX2l3LaYU";
                  }
                  {
                    name = "knife";
                    bookmarks = [
                      {
                        name = "S1xb - Tungsten Carbide (Black coated blade) - Fällkniven";
                        url = "https://fallkniven.se/en/knife/s1xb/";
                      }
                      {
                        name = "Blades Canada - Vancouver, BC";
                        url = "https://www.warriorsandwonders.com/";
                      }
                      {
                        name = "steel";
                        bookmarks = [
                          {
                            name = "Guide to the Best Knife Steel | Knife Informer";
                            url = "https://knifeinformer.com/discovering-the-best-knife-steel/";
                          }
                          {
                            name = "Best Knife Steel Comparison - Steel Charts & Guide | Blade HQ";
                            url = "https://www.bladehq.com/cat--Best-Knife-Steel-Guide--3368";
                          }
                        ];
                      }
                      {
                        name = "Bushcraft Canada";
                        url = "https://www.bushcraftcanada.com/";
                      }
                    ];
                  }
                  {
                    name = "Religion";
                    bookmarks = [
                      {
                        name = "Quantum theory and determinism | SpringerLink";
                        url = "https://link.springer.com/article/10.1007/s40509-014-0008-4";
                      }
                      {
                        name = "Arguments Against the Existence of God (Overview) | Introduction to Philosophy";
                        url = "https://courses.lumenlearning.com/sanjacinto-philosophy/chapter/arguments-against-the-existence-of-god-overview/";
                      }
                      {
                        name = "Q: Can free will exist in our deterministic universe? | Ask a Mathematician / Ask a Physicist";
                        url = "https://www.askamathematician.com/2018/11/q-can-free-will-exist-in-our-deterministic-universe/";
                      }
                      {
                        name = "FREE WILL, DETERMINISM, QUANTUM THEORY AND STATISTICAL FLUCTUATIONS: A PHYSICIST'S TAKE | Edge.org";
                        url = "https://www.edge.org/conversation/carlo_rovelli-free-will-determinism-quantum-theory-and-statistical-fluctuations-a";
                      }
                      {
                        name = "[quant-ph/0604079] The Free Will Theorem";
                        url = "https://arxiv.org/abs/quant-ph/0604079";
                      }
                      {
                        name = "Compatibilism Debunked | Free Will and Determinism - YouTube";
                        url = "https://www.youtube.com/watch?v=Dqj32jxOC0Y";
                      }
                      {
                        name = "Why I'm a Hard Incompatibilist, Not a Hard Determinist. -";
                        url = "https://breakingthefreewillillusion.com/hard-incompatibilist-not-hard-determinist/";
                      }
                      {
                        name = "Free Will is Impossible. Interview with Derk Pereboom - YouTube";
                        url = "https://www.youtube.com/watch?v=f5Ublv0fneY";
                      }
                      {
                        name = "Dallas Willard | Reflections on Dawkins' The Blind Watchmaker";
                        url = "https://dwillard.org/articles/reflections-on-dawkins-the-blind-watchmaker";
                      }
                      {
                        name = "The Longest-Running Evolution Experiment - YouTube";
                        url = "https://www.youtube.com/watch?v=w4sLAQvEH-M";
                      }
                      {
                        name = "How to be an Atheist in Medieval Europe - YouTube";
                        url = "https://www.youtube.com/watch?v=Eb5mYqnKFlI";
                      }
                      {
                        name = "The Catholic Church Just Destroyed Itself with Logic - YouTube";
                        url = "https://www.youtube.com/watch?v=oK7IM7m8oYw";
                      }
                      {
                        name = "Steven Hassan's BITE Model of Authoritarian Control - Freedom of Mind Resource Center";
                        url = "https://freedomofmind.com/cult-mind-control/bite-model/";
                      }
                      {
                        name = "A Wild Story From a Gospel Excluded from the Bible | Gospel of Judas - YouTube";
                        url = "https://www.youtube.com/watch?v=BhQmLFHxsBw";
                      }
                    ];
                  }
                  {
                    name = "covid";
                    bookmarks = [
                      {
                        name = "Covid Trends";
                        url = "https://aatishb.com/covidtrends/?country=Canada&country=China&country=Italy&country=US";
                      }
                      {
                        name = "Situation reports";
                        url = "https://www.who.int/emergencies/diseases/novel-coronavirus-2019/situation-reports";
                      }
                      {
                        name = "Coronavirus COVID-19 (2019-nCoV)";
                        url = "https://gisanddata.maps.arcgis.com/apps/opsdashboard/index.html#/bda7594740fd40299423467b48e9ecf6";
                      }
                      {
                        name = "Daily COVID-19 Dashboard - Ottawa Public Health";
                        url = "https://www.ottawapublichealth.ca/en/reports-research-and-statistics/daily-covid19-dashboard.aspx";
                      }
                      {
                        name = "United States Coronavirus: 2,575,360 Cases and 127,891 Deaths - Worldometer";
                        url = "https://www.worldometers.info/coronavirus/country/us/";
                      }
                    ];
                  }
                  {
                    name = "Don't ask to ask, just ask";
                    url = "https://dontasktoask.com/";
                  }
                  {
                    name = "qarmin/czkawka: Multi functional app to find duplicates, empty folders, similar images etc.";
                    url = "https://github.com/qarmin/czkawka";
                  }
                  {
                    name = "Dataset Search";
                    url = "https://datasetsearch.research.google.com/";
                  }
                  {
                    name = "IntelTechniques Search Tools";
                    url = "https://inteltechniques.com/osintbook9/tools/index.html";
                  }
                  {
                    name = "Food";
                    bookmarks = [
                      {
                        name = "Instant Pot® Chili Recipe | Allrecipes";
                        url = "https://www.allrecipes.com/recipe/264084/instant-pot-chili/";
                      }
                      {
                        name = "Home - Budget Bytes";
                        url = "https://www.budgetbytes.com/";
                      }
                      {
                        name = "100 Food Hacks I Learned In Restaurants - YouTube";
                        url = "https://www.youtube.com/watch?v=H_erG7HSK0A";
                      }
                    ];
                  }
                  {
                    name = "Send Big Files up to 5GB Securely. Tresorit Send: Secure, Fast & Free";
                    url = "https://send.tresorit.com/";
                  }
                  {
                    name = "Warhammer 40,000: Mechanicus | Teaser Trailer - YouTube";
                    url = "https://www.youtube.com/watch?v=9gIMZ0WyY88&t=0s";
                  }
                  {
                    name = "Why Would a Mother Do This? | Law & Order - YouTube";
                    url = "https://www.youtube.com/watch?v=LD_XMbzX3Bg";
                  }
                  {
                    name = "Google, Facebook, Amazon - The rise of the mega-corporations | DW Documentary - YouTube";
                    url = "https://www.youtube.com/watch?v=Dy8ogOaKk4Y";
                  }
                  {
                    name = "Jan. 6 Committee Member Releases Audio Of Threats Made To His Office - YouTube";
                    url = "https://www.youtube.com/watch?v=aNy0moAeX2c";
                  }
                  {
                    name = "Let's talk about the wages of freedom.... - YouTube";
                    url = "https://www.youtube.com/watch?v=RC-_fFq1mQA&list=UU0YvoAYGgdOfySQSLcxtu1w&index=83";
                  }
                  {
                    name = "No more VPN. Introducting Cloudflare Tunnel // Szymon Sakowicz";
                    url = "https://www.sakowi.cz/blog/cloudflared-docker-compose-tutorial";
                  }
                  {
                    name = "Publishing PGP Keys in DNS";
                    url = "https://www.gushi.org/make-dns-cert/HOWTO.html";
                  }
                  {
                    name = "English Cover【JubyPhonic】Kagerou Days カゲロウデイズ - YouTube";
                    url = "https://www.youtube.com/watch?v=MU-rdG-M5Ho";
                  }
                  {
                    name = "Khaki Field Automatic Watch - Black Dial - H70455533 | Hamilton Watch";
                    url = "https://www.hamiltonwatch.com/en-us/h70455533-khaki-field-auto.html";
                  }
                  {
                    name = "CFOP Speedsolving Method";
                    url = "https://jperm.net/3x3/cfop";
                  }
                  {
                    name = "dCode - Online Ciphers, Solvers, Decoders, Calculators";
                    url = "https://www.dcode.fr/en";
                  }
                  {
                    name = "sjvasquez/handwriting-synthesis: Handwriting Synthesis with RNNs ✏️";
                    url = "https://github.com/sjvasquez/handwriting-synthesis";
                  }
                  {
                    name = "It's Time To Put Open Source Photogrammetry In Your Toolbox - YouTube";
                    url = "https://www.youtube.com/watch?v=8wQGbmLulBw";
                  }
                  {
                    name = "The Lie That's Destroying the Economy - YouTube";
                    url = "https://www.youtube.com/watch?v=ayrVYwoe-DY";
                  }
                  {
                    name = "A Cure for Nihilism? | Everything Everywhere All At Once";
                    url = "https://thelivingphilosophy.substack.com/p/a-cure-for-nihilism-everything-everywhere";
                  }
                  {
                    name = "I Couldn't Believe How Rich America Was. We Never Stood A Chance. - YouTube";
                    url = "https://www.youtube.com/watch?v=YL4JIB4CzBw";
                  }
                  {
                    name = "f1";
                    bookmarks = [
                      {
                        name = "The Greatest Innovations In Formula One - YouTube";
                        url = "https://www.youtube.com/watch?v=4NG3qZHx1jM";
                      }
                    ];
                  }
                  {
                    name = "The Game Prototype That Had to Be Banned by Its Own Studio - YouTube";
                    url = "https://www.youtube.com/watch?v=aOYbR-Q_4Hs";
                  }
                  {
                    name = "Stronghold SS50CS Closed Shackle | Boron Hardened Steel Padlock - Squire Locks";
                    url = "https://squirelocksusa.com/collections/strong-hold/products/stronghold-ss50cs?variant=39531773558867";
                  }
                  {
                    name = "The official Ryan McBeth Substack | Substack";
                    url = "https://ryanmcbeth.substack.com/";
                  }
                  {
                    name = "Tedium | An Offbeat Digital Newsletter";
                    url = "https://tedium.co/";
                  }
                  {
                    name = "MyRetroTVs";
                    url = "https://www.myretrotvs.com/";
                  }
                ];
              }
              {
                name = "Briefkasten";
                url = "https://briefkastenhq.com/auth/signin?callbackUrl=https%3A%2F%2Fbriefkastenhq.com%2F&error=OAuthAccountNotLinked";
              }
              {
                name = "typing";
                bookmarks = [
                  {
                    name = "Ngram Type";
                    url = "https://ranelpadon.github.io/ngram-type/";
                  }
                  {
                    name = "Oryx: The ZSA Keyboard Configurator";
                    url = "https://configure.zsa.io/moonlander/layouts/pJmmv/latest/0";
                  }
                  {
                    name = "Monkeytype";
                    url = "https://monkeytype.com/settings";
                  }
                  {
                    name = "Dashboard - EdClub";
                    url = "https://www.edclub.com/sportal/";
                  }
                  {
                    name = "My Profile";
                    url = "https://www.keybr.com/profile";
                  }
                ];
              }
              {
                name = "Warhammer 40k";
                bookmarks = [
                  {
                    name = "How to paint: Chipping, Rust and Mud (Astra Militarum Wyvern/Chimera/Leman Russ) - YouTube";
                    url = "https://www.youtube.com/watch?v=lAQ5T9VQYVE";
                  }
                  {
                    name = "Astra Militarum - Out of the Box Cards";
                    url = "https://www.outoftheboxcards.com/product-category/miniature-gaming/games-workshop/warhammer-40k/astra-militarum/";
                  }
                  {
                    name = "Stop Chipping Like a Potato! - YouTube";
                    url = "https://www.youtube.com/watch?v=LAH5ahKGa3w";
                  }
                  {
                    name = "r/TheAstraMilitarum - Boss, where's the cannon? - Krieg";
                    url = "https://i.redd.it/6244f4o0kl261.jpg";
                  }
                  {
                    name = "Finished my Leman Russ : TheAstraMilitarum";
                    url = "https://www.reddit.com/r/TheAstraMilitarum/comments/o41wi8/finished_my_leman_russ/";
                  }
                  {
                    name = "Speed painting a grimdark Imperial Knight - YouTube";
                    url = "https://www.youtube.com/watch?v=zIEuVBR9bRQ";
                  }
                  {
                    name = "IIavNj2.jpg (JPEG Image, 2756 x 1018 pixels) — Scaled (46%)";
                    url = "https://i.imgur.com/IIavNj2.jpg";
                  }
                  {
                    name = "Core Rules";
                    url = "https://wahapedia.ru/wh40k10ed/the-rules/core-rules/";
                  }
                  {
                    name = "Paint-tech 27 - How to Magnetize the Onager Dunecrawler - YouTube";
                    url = "https://www.youtube.com/watch?v=ph5rphhLVug";
                  }
                  {
                    name = "Magnetising Adeptus Mechanicus Kataphrons - YouTube";
                    url = "https://www.youtube.com/watch?v=KIwe6lWyn-0";
                  }
                  {
                    name = "p6lu8lqzq5t61.png (PNG Image, 827 x 1169 pixels)";
                    url = "https://i.redd.it/p6lu8lqzq5t61.png";
                  }
                  {
                    name = "9th edition Flowchart(2).pdf - Google Drive";
                    url = "https://drive.google.com/file/d/1ggwFq-CeVQj_XfO8S_sPSQHrpuWAtYOE/view";
                  }
                  {
                    name = "How to Deploy in Warhammer 40K 9th Edition - Deployment Phase Tips + Tactics - YouTube";
                    url = "https://www.youtube.com/watch?v=lmaroKwSEfk";
                  }
                  {
                    name = "Adeptus Mechanicus in Warhammer 40K 10th Edition - Full Admech Index Rules and Datasheets Review - YouTube";
                    url = "https://www.youtube.com/watch?v=0SLD1fZyh5s";
                  }
                ];
              }
              {
                name = "Weather";
                bookmarks = [
                  {
                    name = "Windy: Wind map & weather forecast";
                    url = "https://www.windy.com";
                  }
                  {
                    name = "Map - Wood Weather Information System";
                    url = "https://weather.decisionvue.net/";
                  }
                  {
                    name = "The Weather Network - Weather forecasts, maps, news and videos";
                    url = "https://www.theweathernetwork.com/ca";
                  }
                ];
              }
              {
                name = "Laptop";
                bookmarks = [
                  {
                    name = "Preparing the disks - Gentoo Wiki";
                    url = "https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Disks#Partitioning_the_disk_with_GPT_for_UEFI";
                  }
                  {
                    name = "Full Disk Encryption From Scratch Simplified - Gentoo Wiki";
                    url = "https://wiki.gentoo.org/wiki/Full_Disk_Encryption_From_Scratch_Simplified#Creating_partition";
                  }
                  {
                    name = "Btrfs - Gentoo Wiki";
                    url = "https://wiki.gentoo.org/wiki/Btrfs";
                  }
                  {
                    name = "dm-crypt/Encrypting an entire system - ArchWiki";
                    url = "https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#Creating_btrfs_subvolumes";
                  }
                  {
                    name = "Btrfs - ArchWiki";
                    url = "https://wiki.archlinux.org/title/Btrfs#Creating_a_subvolume";
                  }
                  {
                    name = "Reverse Scrolling? : archlinux";
                    url = "https://www.reddit.com/r/archlinux/comments/b64k4s/reverse_scrolling/";
                  }
                  {
                    name = "Ubuntu — How to use Intel Optane Memory for SSD Caching | by Dennis Zimmer | ITNEXT";
                    url = "https://itnext.io/ubuntu-how-to-use-intel-optane-memory-for-ssd-caching-42839b9ab3b9";
                  }
                  {
                    name = "Linux: Get WM_CLASS of Window - Stack Pointer";
                    url = "https://stackpointer.io/unix/linux-get-wm-class-window/628/";
                  }
                  {
                    name = "i3: i3 User's Guide";
                    url = "https://i3wm.org/docs/userguide.html#_mouse_button_commands";
                  }
                  {
                    name = "Automatically sign NVidia Kernel module in Fedora 36 - Monosoul's Dev Blog";
                    url = "https://blog.monosoul.dev/2022/05/17/automatically-sign-nvidia-kernel-module-in-fedora-36/";
                  }
                  {
                    name = "How to Root Snapdragon Galaxy S9, Galaxy S9+, and Galaxy Note 9 (Extreme Syndicate Root Method)";
                    url = "https://www.thecustomdroid.com/snapdragon-galaxy-s9-s9-note-9-root-guide/";
                  }
                  {
                    name = "How to run TrueNAS on Proxmox? - YouTube";
                    url = "https://www.youtube.com/watch?v=M3pKprTdNqQ";
                  }
                  {
                    name = "Turning Proxmox Into a Pretty Good NAS - YouTube";
                    url = "https://www.youtube.com/watch?app=desktop&v=Hu3t8pcq8O0";
                  }
                  {
                    name = "KDE Plasma 5.27 Adds New Tiling System to Place Windows Side-by-Side - FOSTips";
                    url = "https://fostips.com/kde-plasma-5-27-new-tiling-system/";
                  }
                  {
                    name = "Cracking LUKS/dm-crypt passphrases - Diverto - Information Security Warriors";
                    url = "https://diverto.github.io/2019/11/18/Cracking-LUKS-passphrases";
                  }
                  {
                    name = "A very silly CPU monitor - YouTube";
                    url = "https://www.youtube.com/watch?v=4J-DTbZlJ5I";
                  }
                  {
                    name = "Disk Prices (CA)";
                    url = "https://diskprices.com/?locale=ca&condition=new&capacity=8-&disk_types=external_hdd,external_hdd25,internal_hdd,internal_hdd25,external_ssd,internal_ssd,m2_ssd,m2_nvme,u2";
                  }
                  {
                    name = "Compare Prices and Deals on Computer Storage - Storage Price Tracker";
                    url = "https://storagepricetracker.com/";
                  }
                  {
                    name = "gvolpe/nix-config: :space_invader: NixOS configuration";
                    url = "https://github.com/gvolpe/nix-config";
                  }
                  {
                    name = "compose2nix";
                    url = "https://github.com/aksiksi/compose2nix";
                  }
                  {
                    name = "Building the PERFECT Linux PC with Linus Torvalds - YouTube";
                    url = "https://www.youtube.com/watch?v=mfv0V1SxbNA";
                  }
                ];
              }
              {
                name = "Home Assistant";
                bookmarks = [
                  {
                    name = "jakowenko/double-take: Unified UI and API for processing and training images for facial recognition.";
                    url = "https://github.com/jakowenko/double-take";
                  }
                  {
                    name = "This Just Made Face Recognition So Much Better! - YouTube";
                    url = "https://www.youtube.com/watch?v=_61-hIL1AjQ";
                  }
                  {
                    name = "linuxserver/healthchecks - Docker Image | Docker Hub";
                    url = "https://hub.docker.com/r/linuxserver/healthchecks";
                  }
                  {
                    name = "Smartwings Review and Adding Zigbee2mqtt Device Support - YouTube";
                    url = "https://www.youtube.com/watch?v=VJsXc54ZU3o";
                  }
                  {
                    name = "Everything Presence One - Everything Smart Technology";
                    url = "https://shop.everythingsmart.io/en-ca/collections/everything-presence-one";
                  }
                  {
                    name = "naxsi compile · nbs-system/naxsi Wiki";
                    url = "https://github.com/nbs-system/naxsi/wiki/naxsi-compile";
                  }
                  {
                    name = "4 Open Source Web Application Firewall for Better Security";
                    url = "https://geekflare.com/open-source-web-application-firewall/";
                  }
                  {
                    name = "Proxmox VE Helper Scripts | Scripts for Streamlining Your Homelab with Proxmox VE";
                    url = "https://tteck.github.io/Proxmox/";
                  }
                  {
                    name = "jomjol/AI-on-the-edge-device: Easy to use device for connecting \"old\" measuring units (water, power, gas, ...) to the digital world";
                    url = "https://github.com/jomjol/AI-on-the-edge-device";
                  }
                  {
                    name = "Using volumes with rootless podman, explained - Tutorial Works";
                    url = "https://www.tutorialworks.com/podman-rootless-volumes/";
                  }
                  {
                    name = "awesome-selfhosted/awesome-selfhosted: A list of Free Software network services and web applications which can be hosted on your own servers";
                    url = "https://github.com/awesome-selfhosted/awesome-selfhosted#personal-dashboards";
                  }
                  {
                    name = "How to Setup and Secure UniFi VLAN — LazyAdmin";
                    url = "https://lazyadmin.nl/home-network/unifi-vlan-configuration/";
                  }
                  {
                    name = "Ambient Weather WS-5000 Ultrasonic Smart Weather Station";
                    url = "https://ambientweather.com/ws-5000-ultrasonic-smart-weather-station";
                  }
                  {
                    name = "🚘 Garage Fingerprint Sensor - Share your Projects! - Home Assistant Community";
                    url = "https://community.home-assistant.io/t/garage-fingerprint-sensor/312977";
                  }
                  {
                    name = "Workflows | Novu";
                    url = "https://docs.novu.co/platform/workflows";
                  }
                  {
                    name = "How to Set Up Prometheus Monitoring On Kubernetes Cluster";
                    url = "https://devapo.io/blog/technology/how-to-set-up-prometheus-on-kubernetes-with-helm-charts/";
                  }
                  {
                    name = "Free SSL Certs in Kubernetes! Cert Manager Tutorial - YouTube";
                    url = "https://www.youtube.com/watch?v=DvXkD0f-lhY";
                  }
                  {
                    name = "MetalLB and NGINX Ingress // Setup External Access for Kubernetes Applications - YouTube";
                    url = "https://www.youtube.com/watch?v=k8bxtsWe9qw";
                  }
                  {
                    name = "Install and Configure Traefik Ingress Controller on Kubernetes | ComputingForGeeks";
                    url = "https://computingforgeeks.com/install-configure-traefik-ingress-controller-on-kubernetes/";
                  }
                  {
                    name = "Airzone Cloud - Home Assistant";
                    url = "https://www.home-assistant.io/integrations/airzone_cloud/";
                  }
                  {
                    name = "Hardenize Report: weather.decisionvue.net";
                    url = "https://www.hardenize.com/report/weather.decisionvue.net/1699723291#www_csp";
                  }
                  {
                    name = "Temperature Monitoring with the Shelly UNI - THE Swiss Army knife of modules. - YouTube";
                    url = "https://www.youtube.com/watch?v=qtt0W_CP294";
                  }
                  {
                    name = "Wiring the Shelly Plus 1 Relay - HomeTechHacker";
                    url = "https://hometechhacker.com/wiring-the-shelly-plus-1-relay/";
                  }
                  {
                    name = "Install InfluxDB | InfluxDB OSS v2 Documentation";
                    url = "https://docs.influxdata.com/influxdb/v2/install/?t=Docker#install-influxdb-as-a-service-with-systemd";
                  }
                  {
                    name = "Shlink — The URL shortener — Documentation";
                    url = "https://shlink.io/documentation/install-docker-image/";
                  }
                  {
                    name = "Securing Microservice APIs with OAuth2 Proxy: A Complete Project | by Kesara Karannagoda | DevOps.dev";
                    url = "https://blog.devops.dev/securing-microservice-apis-with-oauth2-proxy-a-complete-project-71fabc79147d";
                  }
                ];
              }
              {
                name = "Do People Understand the Scale of the Universe? - YouTube";
                url = "https://www.youtube.com/watch?v=fG8SwAFQFuU";
              }
              {
                name = "Map of Reddit";
                url = "https://anvaka.github.io/map-of-reddit/?x=18239&y=12514&z=23244.04817852816&v=2";
              }
              {
                name = "GitHub - sherlock-project/sherlock: Hunt down social media accounts by username across social networks";
                url = "https://github.com/sherlock-project/sherlock";
              }
              {
                name = "Docker Service not running : r/truenas";
                url = "https://www.reddit.com/r/truenas/comments/mf09bs/docker_service_not_running/";
              }
              {
                name = "[NAS-133437] Failed to start docker for Applications: Docker service could not be started - iXsystems TrueNAS Jira";
                url = "https://ixsystems.atlassian.net/browse/NAS-133437";
              }
            ];
          }
        ];
      };
      search = {
        force = true;
        default = "ddg";
        privateDefault = "ddg";
        engines = {
          "MyNixOS" = {
            definedAliases = [ "@no" ];
            urls = [
              {
                template = "https://mynixos.com/search?q={searchTerms}";
              }
            ];
          };
          "NixOS Packages" = {
            definedAliases = [ "@np" ];
            urls = [
              {
                template = "https://search.nixos.org/packages";
                params = [
                  {
                    name = "type";
                    value = "packages";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
          };
          "NixOS Wiki" = {
            definedAliases = [ "@nw" ];
            urls = [ { template = "https://wiki.nixos.org/w/index.php?search={searchTerms}"; } ];
          };
        };
      };
      extensions =
         let
           firefoxExtensions = [
             bitwarden
             dnssec
             harper
             singleFile
             readAloud
             facebookContainer
             enhancerForYouTube
             duckDuckGoPrivacyEssentials
             simpleLogin
           ];
         in
         {
           force = true;
           packages = firefoxExtensions;
           settings = builtins.listToAttrs (
             map (extension: {
               name = extension.addonId;
               value = with extension; {
                 inherit permissions;
               };
             }) firefoxExtensions
           );
         };
    };
  };
}
