_:

{
  environment.etc."avahi/services/ssh.service".text = ''<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_ssh._tcp</type>
    <port>22</port>
  </service>
</service-group>
'';
  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    fail2ban.enable = true;
  };
  users.users = {
    daniel.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPOhOXM61fK+PiqPSD8eZ+cW0ACcl8IeBJO14odVsmVU daniel@onion"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID8N4zSVA9MvNfdBlloRyFCazPH09qlkyCZ+6xTe2Cce daniel@melon"
    ];
  };
}
