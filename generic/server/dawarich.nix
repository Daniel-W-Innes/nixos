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
      };
    };
    nominatim = {
      enable = true;
      hostName = "nominatim.lc.brotherwolf.ca";
      ui = {
        config = ''
          Nominatim_Config.Page_Title='Nominatim instance';
          Nominatim_Config.Nominatim_API_Endpoint='https://localhost:4443/';
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
