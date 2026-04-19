{
  config,
  cudaSupport ? config.cudaSupport or false,
  cudaPackages,
  fetchurl,
  xz,
  gnutar,
  stdenv,
  fetchFromGitHub,
  runCommand,
  buildNpmPackage,
  cmake,
  pkg-config,
  python3,
  makeWrapper,
  wayland-scanner,
  autoPatchelfHook,
  autoAddDriverRunpath,
  avahi,
  libevdev,
  libpulseaudio,
  openssl,
  libopus,
  libdrm,
  wayland,
  libffi,
  libcap,
  curl,
  pcre,
  pcre2,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  xorg,
  libxkbcommon,
  libepoxy,
  libva,
  libvdpau,
  numactl,
  libgbm,
  amf-headers,
  sysprof,
  glib,
  svt-av1,
  lib,
  libappindicator,
  libappindicator-gtk3,
  vulkan-loader,
  libglvnd,
  libnotify,
  coreutils,
  miniupnpc,
  nlohmann_json,
}: let
  # Pre-fetch the boost dependency to circumvent the problem with boost188 package.
  # This relies on CmakeLists FetchContent
  boostVersion = "1.88.0";
  boostCMakeTarballURL = "https://github.com/boostorg/boost/releases/download/boost-${boostVersion}/boost-${boostVersion}-cmake.tar.xz";

  boostFetchedTarball = fetchurl {
    url = boostCMakeTarballURL;
    hash = "sha256-9ItIOQOAz7lKYphyNG46gTcNxJiJbxYBmt5yercusew=";
  };

  boostExtractedSrc =
    runCommand "boost-${boostVersion}-cmake-src" {
      src = boostFetchedTarball;
      nativeBuildInputs = [gnutar xz];
    } ''
      mkdir -p $out
      tar -xf $src --strip-components=1 -C $out
    '';

  stdenv' =
    if cudaSupport
    then cudaPackages.backendStdenv
    else stdenv;
in
  stdenv'.mkDerivation rec {
    pname = "sunshine";
    version = "master";

    src = fetchFromGitHub {
      owner = "ClassicOldSong";
      repo = "Apollo";
      rev = "5af771d29e986e3604cf74b51ac81cba5b0bd3ee";
      hash = "sha256-PWlXoYa6B7yVRwhS32uG51ktG11pifgzgVspchR/W1I=";
      fetchSubmodules = true;
    };

    ui = buildNpmPackage {
      inherit src version;
      pname = "apollo-ui";
      npmDepsHash = "sha256-OM3LB8SUX5C5tnyb00amFtfePoLrRumLpAl05Ur9Rz4=";

      postPatch = ''
        cp ${./package-lock.json} ./package-lock.json
      '';

      installPhase = ''
        mkdir -p $out
        cp -r * $out/
      '';
    };

    nativeBuildInputs =
      [
        cmake
        pkg-config
        python3
        makeWrapper
        wayland-scanner
        autoPatchelfHook
      ]
      ++ lib.optionals cudaSupport [
        autoAddDriverRunpath
        cudaPackages.cuda_nvcc
        (lib.getDev cudaPackages.cuda_cudart)
      ];

    buildInputs =
      [
        avahi
        libevdev
        libpulseaudio
        xorg.libX11
        xorg.libxcb
        xorg.libXfixes
        xorg.libXrandr
        xorg.libXtst
        xorg.libXi
        openssl
        libopus
        libdrm
        wayland
        libffi
        libcap
        curl
        pcre
        pcre2
        libuuid
        libselinux
        libsepol
        libthai
        libdatrie
        xorg.libXdmcp
        libxkbcommon
        libepoxy
        libva
        libvdpau
        numactl
        libgbm
        amf-headers
        sysprof
        glib
        svt-av1
        (
          if lib ? libappindicator
          then libappindicator
          else libappindicator-gtk3
        )
        libnotify
        miniupnpc
        nlohmann_json
      ]
      ++ lib.optionals cudaSupport [
        cudaPackages.cudatoolkit
        cudaPackages.cuda_cudart
      ];

    runtimeDependencies = [
      avahi
      libgbm
      xorg.libXrandr
      xorg.libxcb
      libglvnd
    ];

    cmakeFlags =
      [
        "-Wno-dev"
        (lib.cmakeBool "UDEV_FOUND" true)
        (lib.cmakeBool "SYSTEMD_FOUND" true)
        (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
        (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
        (lib.cmakeBool "BOOST_USE_STATIC" false)
        (lib.cmakeBool "BUILD_DOCS" false)
        (lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "nixpkgs")
        (lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://nixos.org")
        (lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/NixOS/nixpkgs/issues")
        "-DFETCHCONTENT_SOURCE_DIR_BOOST=${boostExtractedSrc}"
      ]
      ++ lib.optionals (!cudaSupport) [
        (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" false)
      ];

    env = {
      BUILD_VERSION = "${version}";
      BRANCH = "master";
      COMMIT = "";
    };

    postPatch = ''
      substituteInPlace cmake/packaging/linux.cmake \
        --replace-fail 'find_package(Systemd)' "" \
        --replace-fail 'find_package(Udev)' ""
      substituteInPlace cmake/targets/common.cmake \
        --replace-fail 'find_program(NPM npm REQUIRED)' ""
      substituteInPlace packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
        --subst-var-by PROJECT_NAME 'Sunshine' \
        --subst-var-by PROJECT_DESCRIPTION 'Self-hosted game stream host for Moonlight' \
        --subst-var-by SUNSHINE_DESKTOP_ICON 'sunshine' \
        --subst-var-by CMAKE_INSTALL_FULL_DATAROOTDIR "$out/share" \
        --replace-fail '/usr/bin/env systemctl start --u sunshine' 'sunshine'
      substituteInPlace packaging/linux/sunshine.service.in \
        --subst-var-by PROJECT_DESCRIPTION 'Self-hosted game stream host for Moonlight' \
        --subst-var-by SUNSHINE_EXECUTABLE_PATH $out/bin/sunshine \
        --replace-fail '/bin/sleep' '${lib.getExe' coreutils "sleep"}'
    '';

    preBuild = ''
      cp -r ${ui}/build ../
    '';

    buildFlags = ["sunshine"];

    postFixup = lib.optionalString cudaSupport ''
      wrapProgram $out/bin/sunshine \
        --set LD_LIBRARY_PATH ${lib.makeLibraryPath [vulkan-loader]}
    '';

    installPhase = ''
      runHook preInstall
      cmake --install .
      runHook postInstall
    '';

    postInstall = ''
      install -Dm644 ../packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
        $out/share/applications/${pname}.desktop
    '';

    meta = with lib; {
      description = "Apollo is a Game stream host for Moonlight";
      homepage = "https://github.com/ClassicOldSong/Apollo";
      license = licenses.gpl3Only;
      mainProgram = "sunshine";
      maintainers = with maintainers; [nil-andreas];
      platforms = platforms.linux;
    };
  }
