{
  config,
  lib,
  librewxr,
  pkgs,
  ...
}:

let
  cfg = config.services.librewxr;
  py = pkgs.python3Packages;

  multiurl = py.buildPythonPackage rec {
    pname = "multiurl";
    version = "0.3.7";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/93/cf/be4e93afbfa0def2cd6fac9302071db0bd6d0617999ecbf53f92b9398de3/multiurl-${version}-py3-none-any.whl";
      hash = "sha256-BU9Cl0Bk8QO+DtVbQ/DDL8Q1pH3HNTqa2v+mQ7mfo4A=";
    };

    dependencies = with py; [
      requests
      tqdm
      pytz
      python-dateutil
    ];

    pythonImportsCheck = [ "multiurl" ];
  };

  earthkit-regrid = py.buildPythonPackage rec {
    pname = "earthkit-regrid";
    version = "0.5.1";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/72/26/ed2a19b8d2b20033120bf85d27c83a34b2a38df11309266497593a14ef79/earthkit_regrid-${version}-py3-none-any.whl";
      hash = "sha256-iBy+j6R+u/29NCXNqnwansc0AyzWP3N+YDes5PfHkU0=";
    };

    dependencies = with py; [
      filelock
      scipy
      multiurl
    ];

    pythonImportsCheck = [ "earthkit.regrid" ];
  };

  cfgrib = py.buildPythonPackage rec {
    pname = "cfgrib";
    version = "0.9.15.1";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/6d/e8/16c58c57c9ce1474dd1e50090ebd78b008c70fc4f06793da65f9a0aba391/cfgrib-${version}-py3-none-any.whl";
      hash = "sha256-8b7pDoaRc4m+n3ZwUb8y0A+V9vTkMSs0RWdRGzz9YtI=";
    };

    buildInputs = [ pkgs.eccodes ];

    dependencies =
      (with py; [
        attrs
        click
        numpy
        xarray
      ])
      ++ [
        python-eccodes
      ];

    preCheck = ''
      export ECCODES_DIR=${pkgs.eccodes}
      export ECCODES_PYTHON_USE_FINDLIBS=1
    '';

    pythonImportsCheck = [ ];
  };

  omfiles = py.buildPythonPackage rec {
    pname = "omfiles";
    version = "1.2.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/8a/f2/d64d9f3424ccbcc94850fcaca04de05d1dd7db8d1c5bbfda63ee37159c3e/omfiles-${version}-cp310-abi3-manylinux_2_28_x86_64.whl";
      hash = "sha256-UlCC7b99WD0CFbmTDevOo63dHLmRRLYQpfABkaEZHTk=";
    };

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];

    dependencies = with py; [
      dask
      fsspec
      numcodecs
      numpy
      pyproj
      s3fs
      xarray
      zarr
    ];

    pythonImportsCheck = [ "omfiles" ];
  };

  findlibs = py.buildPythonPackage rec {
    pname = "findlibs";
    version = "0.1.2";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/2f/ff/76dd547e129206899e4e26446c3ca7aeaff948c31b05250e9b8690e76883/findlibs-${version}-py3-none-any.whl";
      hash = "sha256-U0i7xwVdKlBZYldsLihbbAqubXSfgrpxKW59QTNuZug=";
    };

    pythonImportsCheck = [ "findlibs" ];
  };

  python-eccodes = py.buildPythonPackage rec {
    pname = "eccodes";
    version = "2.47.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/b3/a3/f58ff573ba0f678ff8116686e868afe436627b19b457a2aba62cd463c9ad/eccodes-${version}-py3-none-any.whl";
      hash = "sha256-E9Cyi9WOlOLDA/QkFcoNzFarP+vw9SsfsPHUql59uOE=";
    };

    buildInputs = [ pkgs.eccodes ];

    dependencies = with py; [
      attrs
      cffi
      findlibs
      numpy
    ];

    preCheck = ''
      export ECCODES_DIR=${pkgs.eccodes}
      export ECCODES_PYTHON_USE_FINDLIBS=1
    '';

    pythonImportsCheck = [ ];
  };

  librewxr-python = py.buildPythonApplication rec {
    pname = "librewxr";
    version = "0.1.0";
    pyproject = true;
    src = librewxr;

    nativeBuildInputs = [
      py.hatchling
      py.pythonRelaxDepsHook
    ];
    buildInputs = [ pkgs.eccodes ];

    dependencies = with py; [
      aiobotocore
      botocore
      cfgrib
      earthkit-regrid
      fastapi
      h5py
      httpx
      lxml
      netcdf4
      numpy
      omfiles
      opencv-python-headless
      pillow
      psutil
      pydantic-settings
      rich
      s3fs
      shapely
      uvicorn
      xarray
    ];

    preCheck = ''
      export ECCODES_DIR=${pkgs.eccodes}
      export ECCODES_PYTHON_USE_FINDLIBS=1
    '';

    doCheck = false;
    pythonRelaxDeps = [
      "aiobotocore"
      "botocore"
      "psutil"
    ];
    pythonImportsCheck = [ ];
  };

  librewxr-pythonpath = py.makePythonPath librewxr-python.propagatedBuildInputs;

  librewxr-package = pkgs.writeShellApplication {
    name = "librewxr";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export PYTHONPATH="${librewxr-python}/${pkgs.python3.sitePackages}:${librewxr-pythonpath}"''${PYTHONPATH:+:$PYTHONPATH}
      exec ${pkgs.python3}/bin/python -m librewxr.main "$@"
    '';
  };

  frontendHtml = builtins.replaceStrings
    [
      "<option value=\"local\">Local (localhost:8080)</option>"
      "<option value=\"public\">Public (api.librewxr.net)</option>"
      "    local: 'http://localhost:8080',"
      "    public: 'https://api.librewxr.net'"
    ]
    [
      "<option value=\"local\">LibreWXR</option>"
      "<option value=\"public\">LibreWXR</option>"
      "    local: '${cfg.publicUrl}',"
      "    public: '${cfg.publicUrl}'"
    ]
    (builtins.readFile "${librewxr}/examples/leaflet.html");

  frontendPackage = pkgs.writeTextDir "index.html" frontendHtml;

in
{
  options.services.librewxr = {
    enable = lib.mkEnableOption "LibreWXR weather tile service";

    package = lib.mkOption {
      type = lib.types.package;
      default = librewxr-package;
      description = "Package used to run LibreWXR.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for LibreWXR.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8098;
      description = "Port for LibreWXR.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://librewxr.lc.brotherwolf.ca";
      description = "Public base URL advertised by LibreWXR.";
    };

    enabledRegions = lib.mkOption {
      type = lib.types.str;
      default = "US,CANADA";
      description = "LibreWXR region selection.";
    };

    frontend = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to serve the LibreWXR Leaflet frontend.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Bind address for the LibreWXR frontend.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8099;
        description = "Port for the LibreWXR frontend.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = frontendPackage;
        description = "Static frontend package to serve for LibreWXR.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.librewxr = {
      isSystemUser = true;
      group = "librewxr";
    };
    users.groups.librewxr = { };

    systemd.services.librewxr = {
      description = "LibreWXR weather tile service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        LIBREWXR_CACHE_DIR = "/var/lib/librewxr/cache";
        LIBREWXR_ENABLED_REGIONS = cfg.enabledRegions;
        LIBREWXR_HOST = cfg.host;
        LIBREWXR_PORT = toString cfg.port;
        LIBREWXR_PUBLIC_URL = cfg.publicUrl;
        ECCODES_DIR = "${pkgs.eccodes}";
        ECCODES_PYTHON_USE_FINDLIBS = "1";
      };

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        CacheDirectory = "librewxr";
        Group = "librewxr";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RestartSec = "10s";
        StateDirectory = "librewxr";
        User = "librewxr";
        WorkingDirectory = "/var/lib/librewxr";
      };
    };

    systemd.services.librewxr-frontend = lib.mkIf cfg.frontend.enable {
      description = "LibreWXR Leaflet frontend";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = ''
          ${pkgs.python3}/bin/python -m http.server ${toString cfg.frontend.port} \
            --bind ${cfg.frontend.host} \
            --directory ${cfg.frontend.package}
        '';
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
