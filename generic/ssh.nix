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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIPYmrcC2u9UBj5i9l7aPu7AJJRto0+0jBbDc3TXzUSv daniel@onion"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHj7eEivrU4ow1BNNimeqqdTrvvs3S/NBqmqFPF6jnQu daniel@cucamelon"
    ];
    # builder = {
    #   openssh.authorizedKeys.keys = [
    #     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIDUFABBp2m+PBPjFLgfxl/wMqJCPFrRo6IdaZBjXak root@cucamelon"
    #     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKJ/3supKCAMepABGirEn8gvoJ2Iv/zw/8Bw3oJxydxU root@cucamelon"
    #   ];
    #   isNormalUser = true;
    #   description = "Distributed build";
    # };
  };
}
