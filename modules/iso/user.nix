{pkgs, ...}: {
  programs.zsh.enable = true;
  users.users.szn = {
    name = "szn";
    description = "szn";

    uid = 1000;
    shell = pkgs.zsh;
    isNormalUser = true;
    
    initialPassword = "123!"; # Change this password after first login
    extraGroups = [ "networkmanager" "wheel" "uinput" "docker" ];
    packages = with pkgs; [];
  };
}