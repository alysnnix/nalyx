{ config, pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      jdk21

      maven
      gradle

      # C++ compiler cache for React Native Android builds. The RN CMake
      # scripts run find_program(ccache) and, when it resolves, wire it as
      # RULE_LAUNCH_COMPILE. Without it every clean build recompiles the C++ of
      # reanimated, screens, gesture-handler and the Nitro modules from zero.
      ccache

      jdt-language-server

      google-java-format
      checkstyle
    ];

    sessionVariables = {
      JAVA_HOME = "${pkgs.jdk21}/lib/openjdk";
      JDK_HOME = "${pkgs.jdk21}/lib/openjdk";

      # A single clean Android build fills ~2 GB of objects per ABI, so the 5 GB
      # ccache default evicts the entries a rebuild would have hit.
      CCACHE_MAXSIZE = "20G";

      # NDK objects carry absolute paths from the .cxx directory, so the same
      # source compiled in two git worktrees hashes differently and every
      # worktree pays a full C++ build. Hashing relative to the checkout root
      # instead makes those hits land; the sloppiness list is what ccache
      # documents for builds that regenerate headers on every run.
      CCACHE_BASEDIR = config.home.homeDirectory;
      CCACHE_NOHASHDIR = "1";
      CCACHE_SLOPPINESS = "time_macros,include_file_mtime,include_file_ctime";
    };

    sessionPath = [
      "$JAVA_HOME/bin"
    ];
  };
}
