{
  config,
  ...
}:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  boot.kernelParams = [
    # A BAR1 desta placa nasce com 256 MiB, e o driver vaza mapeamentos de BAR1
    # do processo de GPU do Chrome ao longo do dia. Quando o espaço de endereços
    # da BAR1 acaba, __nv_drm_gem_nvkms_map pede uma faixa que passa do fim da
    # BAR1 e invade a BAR3, o kernel rejeita ("mapping multiple BARs"), e a
    # partir daí é cascata: Xid 31 (MMU fault) -> RPC do GSP sem resposta ->
    # Xid 154 (GPU Reset Required) -> Xid 16 (vblank parado). A tela morre e só
    # o botão de power resolve.
    #
    # A 3060 Ti anuncia BAR redimensionável até 8 GiB (resource1_resize =
    # 0x3fc0), o tamanho da VRAM inteira, o que tira o teto desse caminho.
    # Depende de "Above 4G Decoding" e "Re-Size BAR Support" ligados na BIOS:
    # sem os dois, este parâmetro não tem o que redimensionar e a BAR1 continua
    # em 256 MiB. Conferir depois do boot com:
    #   nvidia-smi -q -d MEMORY | grep -A3 'BAR1 Memory Usage'
    "nvidia.NVreg_EnableResizableBar=1"

    # O que transforma a falha acima em travamento total da máquina é o GSP:
    # quando a RPC para o firmware não volta, o próprio caminho de reset fica
    # preso segurando o lock do RM, e todo cliente novo (compositor, nvidia-smi,
    # até o shutdown) entra em D-state atrás dele. Com o firmware desligado a RM
    # roda na CPU e a falha volta a ser recuperável em vez de fatal.
    #
    # Só existe no módulo proprietário: o open exige GSP e ignora este
    # parâmetro, então o `open = false` abaixo é requisito, não preferência.
    "nvidia.NVreg_EnableGpuFirmware=0"
  ];

  hardware.nvidia = {
    modesetting.enable = true;
    # Requisito do NVreg_EnableGpuFirmware=0 acima.
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Instala os hooks de suspend/resume que salvam e restauram a VRAM. Não tem
    # relação com downclock em idle: quem decide clock ocioso é o PowerMizer,
    # dentro do driver, sem opção de NixOS envolvida.
    powerManagement.enable = true;
    # Desligar a GPU no ocioso é caminho de laptop Optimus. Num desktop com o
    # monitor pendurado nela, só adiciona transição de estado para dar errado.
    powerManagement.finegrained = false;
  };
}
