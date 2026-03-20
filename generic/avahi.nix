_: {
	services.avahi = {
		enable = true;
		nssmdns4 = true;
		nssmdns6 = true;
		openFirewall = true;
		publish = {
			enable = true;
			addresses = true;
			domain = true;
			userServices = true;
			workstation = true;
		};
	};
}