{ pkgs, ... }:

# Local Ollama inference server, CUDA-accelerated.
#
# WSL note: no NVIDIA kernel driver is installed here (the WSL2 kernel handles
# GPU passthrough via /dev/dxg). The userspace CUDA libs come from the Windows
# driver, exposed at /run/opengl-driver/lib by `wsl.useWindowsDriver = true`
# in the host config. `ollama-cuda`'s runpath resolves libcuda.so.1 there, so
# selecting `pkgs.ollama-cuda` works without any hardware.nvidia setup.
#
# The default 127.0.0.1:11434 bind is exactly what omp's implicit Ollama
# discovery probes, so pulled models appear in omp as `ollama/<model>` with no
# omp-side config.
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;

    # Pulled on activation so the model is ready to serve after a rebuild.
    # qwen2.5vl:7b (~6GB, Q4) is the largest vision model that runs fluidly in
    # the RTX 3060 Ti's 8GB VRAM.
    loadModels = [ "qwen2.5vl:7b" ];
  };
}
