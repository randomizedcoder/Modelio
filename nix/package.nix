{
  lib,
  stdenv,
  jdk,
  maven,
  jdk11,
  makeWrapper,
  wrapGAppsHook3,
  autoPatchelfHook,
  gtk3,
  glib,
  xorg,
  freetype,
  fontconfig,
  zlib,
  libsecret,
  webkitgtk_4_0,
  libGL,
  alsa-lib,
  copyDesktopItems,
  makeDesktopItem,
}:

let
  pname = "modelio";
  version = "5.4.1";

  # Phase A: Fixed-output derivation to cache Maven/Tycho dependencies.
  # After the first build attempt, replace lib.fakeHash with the real hash
  # from the error message.
  mvnDeps = stdenv.mkDerivation {
    pname = "${pname}-maven-deps";
    inherit version;
    inherit src;

    nativeBuildInputs = [
      maven
      jdk11
    ];

    buildPhase = ''
      runHook preBuild

      export HOME=$(mktemp -d)

      # Generate toolchains.xml for Tycho
      mkdir -p $HOME/.m2
      cat > $HOME/.m2/toolchains.xml <<XML
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

      export JAVA_HOME="${jdk11}"

      # Create missing directories referenced in build.properties bin.includes (not tracked by git)
      find . -name build.properties -exec sh -c '
        dir=$(dirname "$1")
        grep -A100 "^bin\.includes" "$1" | \
          sed "/^[a-zA-Z]/{ /^bin\.includes/!q; }" | \
          tr "," "\n" | sed "s/.*=//; s/\\\\//; s/^[[:space:]]*//; s/[[:space:]]*$//" | \
          grep "/" | grep -v "^\." | while read -r entry; do
            entry="''${entry%/}"
            [ ! -e "$dir/$entry" ] && mkdir -p "$dir/$entry"
          done
      ' _ {} \;

      # Build everything, caching deps into $out
      mvn install \
        -f AGGREGATOR/pom.xml \
        -t $HOME/.m2/toolchains.xml \
        -Dmaven.repo.local=$out/.m2/repository \
        -DskipTests \
        -Dtycho.localArtifacts=ignore \
        --batch-mode

      mvn package \
        -f products/pom.xml \
        -Pproduct.org,platform.linux \
        -t $HOME/.m2/toolchains.xml \
        -Dmaven.repo.local=$out/.m2/repository \
        -DskipTests \
        --batch-mode

      runHook postBuild
    '';

    installPhase = ''
      # deps are already in $out/.m2/repository from buildPhase
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-pHS8OIdOXixwBBCH4detJMbZEduX54xekzg3NcK3+DA=";

    impureEnvVars = lib.fetchers.proxyImpureEnvVars;
  };

  src = lib.cleanSourceWith {
    src = ./..;
    filter =
      path: type:
      let
        relPath = lib.removePrefix (toString ./..) path;
      in
      # Exclude nix files and git from the source
      !(lib.hasPrefix "/nix" relPath)
      && !(lib.hasPrefix "/flake" relPath)
      && !(lib.hasPrefix "/.git" relPath)
      && !(lib.hasSuffix ".nix" relPath)
      && !(lib.hasSuffix "flake.lock" relPath);
  };

in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    maven
    jdk11
    makeWrapper
    wrapGAppsHook3
    autoPatchelfHook
    copyDesktopItems
  ];

  buildInputs = [
    gtk3
    glib
    xorg.libX11
    xorg.libXtst
    xorg.libXrender
    xorg.libXi
    xorg.libXext
    xorg.libXxf86vm
    freetype
    fontconfig
    zlib
    libsecret
    webkitgtk_4_0
    libGL
    alsa-lib
    stdenv.cc.cc.lib # libstdc++
  ];

  dontWrapGApps = true;

  buildPhase = ''
    runHook preBuild

    export HOME=$(mktemp -d)

    # Generate toolchains.xml
    mkdir -p $HOME/.m2
    cat > $HOME/.m2/toolchains.xml <<XML
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

    export JAVA_HOME="${jdk11}"

    # Create missing directories referenced in build.properties bin.includes (not tracked by git)
    find . -name build.properties -exec sh -c '
      dir=$(dirname "$1")
      grep -A100 "^bin\.includes" "$1" | \
        sed "/^[a-zA-Z]/{ /^bin\.includes/!q; }" | \
        tr "," "\n" | sed "s/.*=//; s/\\\\//; s/^[[:space:]]*//; s/[[:space:]]*$//" | \
        grep "/" | grep -v "^\." | while read -r entry; do
          entry="''${entry%/}"
          [ ! -e "$dir/$entry" ] && mkdir -p "$dir/$entry"
        done
    ' _ {} \;

    # Copy cached deps to writable location (Tycho needs to create .tycholock files)
    cp -r ${mvnDeps}/.m2/repository $HOME/.m2/repository
    chmod -R u+w $HOME/.m2/repository

    # Build using cached dependencies (offline)
    mvn install \
      -f AGGREGATOR/pom.xml \
      -t $HOME/.m2/toolchains.xml \
      -Dmaven.repo.local=$HOME/.m2/repository \
      --offline \
      -DskipTests \
      -Dtycho.localArtifacts=ignore \
      --batch-mode

    mvn package \
      -f products/pom.xml \
      -Pproduct.org,platform.linux \
      -t $HOME/.m2/toolchains.xml \
      -Dmaven.repo.local=$HOME/.m2/repository \
      --offline \
      -DskipTests \
      --batch-mode

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Extract the product tarball
    tarball=$(find products/target/products -name '*linux*tar.gz' | head -1)
    if [ -z "$tarball" ]; then
      echo "ERROR: No linux tarball found in products/target/products/"
      find products/target/ -name '*.tar.gz' || true
      exit 1
    fi

    mkdir -p $out/lib
    tar xf "$tarball" -C $out/lib
    mv "$out/lib/Modelio 5.4.1" $out/lib/modelio

    # Replace bundled JRE with Nix JDK
    rm -rf $out/lib/modelio/jre
    ln -s ${jdk} $out/lib/modelio/jre

    # Create wrapper script
    mkdir -p $out/bin
    makeWrapper $out/lib/modelio/modelio $out/bin/modelio \
      "''${gappsWrapperArgs[@]}" \
      --set JAVA_HOME "${jdk}" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          gtk3
          glib
          xorg.libX11
          xorg.libXtst
          xorg.libXrender
          xorg.libXi
          xorg.libXext
          xorg.libXxf86vm
          freetype
          fontconfig
          zlib
          libsecret
          webkitgtk_4_0
          libGL
          alsa-lib
          stdenv.cc.cc.lib
        ]
      }" \
      --add-flags "-Xms1024m" \
      --add-flags "-Xmx4096m" \
      --add-flags "-Dpython.console.encoding=UTF-8" \
      --add-flags "-Dorg.eclipse.swt.internal.webkitgtk.ignoretlserrors=true"

    # Install icon
    install -Dm644 products/icons/modelio.xpm $out/share/pixmaps/modelio.xpm

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "modelio";
      desktopName = "Modelio";
      exec = "modelio";
      icon = "modelio";
      comment = "Open-source UML/BPMN modeling tool";
      categories = [
        "Development"
        "IDE"
      ];
    })
  ];

  meta = {
    description = "Open-source modeling environment (UML, BPMN, ArchiMate)";
    homepage = "https://www.modelio.org";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "modelio";
  };
}
