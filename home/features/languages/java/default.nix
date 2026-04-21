{ pkgs, ... }:

{
  home = {
    packages = with pkgs; [
      jdk21

      maven
      gradle

      jdt-language-server

      google-java-format
      checkstyle
    ];

    sessionVariables = {
      JAVA_HOME = "${pkgs.jdk21}/lib/openjdk";
      JDK_HOME = "${pkgs.jdk21}/lib/openjdk";
    };

    sessionPath = [
      "$JAVA_HOME/bin"
    ];
  };
}
