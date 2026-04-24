_:

{
  services = {
    dawarich = {
      enable = true;
      localDomain = "dawarich.lc.brotherwolf.ca";
      configureNginx = false;
      webPort = 3080;
      environment = {
        STORE_GEODATA = "true";
        TIME_ZONE = "America/Toronto";
        NOMINATIM_API_HOST = "nominatim.lc.brotherwolf.ca:4443";
        NOMINATIM_API_USE_HTTPS = "true";
      };
    };
    nominatim = {
      enable = true;
      hostName = "nominatim.lc.brotherwolf.ca";
      ui = {
        config = ''
          Nominatim_Config.Page_Title='Nominatim instance';
          Nominatim_Config.Nominatim_API_Endpoint='https://nominatim.lc.brotherwolf.ca:4443/';
        '';
      };
    };
    nginx.defaultSSLListenPort = 4443;
    nginx.defaultHTTPListenPort = 4080;
  };
  networking.firewall.allowedTCPPorts = [ 4443 ];
  security.acme = {
    defaults.email = "companies+letsencrypt@brotherwolf.ca";
    acceptTerms = true;
  };
}
