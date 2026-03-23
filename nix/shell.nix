{
  mkShell,
  maven,
  jdk11,
  gtk3,
  glib,
  xorg,
  freetype,
  fontconfig,
  zlib,
  libsecret,
}:

mkShell {
  packages = [
    maven
    jdk11
  ];

  buildInputs = [
    gtk3
    glib
    xorg.libX11
    xorg.libXtst
    xorg.libXrender
    freetype
    fontconfig
    zlib
    libsecret
  ];

  shellHook = ''
    export JAVA_HOME="${jdk11}"

    # Auto-generate toolchains.xml for Tycho
    mkdir -p "$HOME/.m2"
    cat > "$HOME/.m2/toolchains.xml" <<XML
    <?xml version="1.0" encoding="UTF-8"?>
    <toolchains xmlns="http://maven.apache.org/TOOLCHAINS/1.1.0"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://maven.apache.org/TOOLCHAINS/1.1.0
        http://maven.apache.org/xsd/toolchains-1.1.0.xsd">
      <toolchain>
        <type>jdk</type>
        <provides>
          <version>1.8</version>
          <vendor>adoptOpenJDK</vendor>
          <id>JavaSE-1.8</id>
        </provides>
        <configuration>
          <jdkHome>${jdk11}</jdkHome>
        </configuration>
      </toolchain>
      <toolchain>
        <type>jdk</type>
        <provides>
          <version>11</version>
          <vendor>adoptOpenJDK</vendor>
          <id>JavaSE-11</id>
        </provides>
        <configuration>
          <jdkHome>${jdk11}</jdkHome>
        </configuration>
      </toolchain>
    </toolchains>
    XML

    echo "Modelio dev shell"
    echo "  JAVA_HOME=$JAVA_HOME"
    echo "  java:  $(java -version 2>&1 | head -1)"
    echo "  maven: $(mvn --version 2>&1 | head -1)"
    echo ""
    echo "Build steps:"
    echo "  1. mvn clean install -f AGGREGATOR/pom.xml"
    echo "  2. mvn package -f products/pom.xml -Pproduct.org,platform.linux"
    echo "  Output: products/target/products/*linux*.tar.gz"
  '';
}
