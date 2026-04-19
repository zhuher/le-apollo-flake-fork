{
  config,
  cudaSupport ? config.cudaSupport or false,
  cudaPackages,
  stdenv,
  fetchFromGitHub,
  buildNpmPackage,
  cmake,
  pkg-config,
  python3,
  makeWrapper,
  wayland-scanner,
  autoPatchelfHook,
  autoAddDriverRunpath,
  avahi,
  libdeflate,
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
  boost189,
  libsysprof-capture,
  lerc,
  symlinkJoin,
  icu,
  libX11,
  libXtst,
  libXdmcp,
  xz,
  libwebp,
  udevCheckHook,
  libXrandr,
  libxcb,
  libXfixes,
  libXi,
}: let
  inherit (stdenv.hostPlatform) isLinux;
  stdenv' =
    if cudaSupport
    then cudaPackages.backendStdenv
    else stdenv;
  hroost =
    boost189
    # .override {
    #   enableShared = false;
    #   enableStatic = true;
    # }
    #
    ;
  # [INFO] cmake only looks in .dev and fails to find the library files, so gotta bring them in from the separate .out
  # haven't found a way to use them in separation.
  boost = symlinkJoin {
    name = "boost-combined-1.89.0";
    paths = [hroost.dev hroost.out];
  };
in
  stdenv'.mkDerivation (finalAttrs: {
    pname = "apollo";
    version = "master";
    src = fetchFromGitHub {
      owner = "ClassicOldSong";
      repo = "Apollo";
      rev = "dd99a82247de72ad16b8804ae85822ddc8222c3a";
      hash = "sha256-1nRB3GrEm97u0c1cvQ5QoTPcu/NxgOwJoSGCK16bRmI=";
      # rev = "5af771d29e986e3604cf74b51ac81cba5b0bd3ee";
      # hash = "sha256-PWlXoYa6B7yVRwhS32uG51ktG11pifgzgVspchR/W1I=";
      fetchSubmodules = true;
    };
    patches = [
      ./boost-189-log_setup-no-system.patch
    ];
    # build webui
    ui = buildNpmPackage {
      inherit (finalAttrs) src version;
      pname = "apollo-ui";
      npmDepsHash = "sha256-KqD6pjW7qLNXQU1gqIEazZENQ/OKCvOu7fsXpzMINkM=";

      # use generated package-lock.json as upstream does not provide one
      postPatch = ''
        cp ${./package-lock.json} ./package-lock.json
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out"
        cp -a . "$out"/

        runHook postInstall
      '';
    };

    postPatch =
      # don't look for npm since we build webui separately
      ''
        substituteInPlace cmake/targets/common.cmake \
          --replace-fail 'find_program(NPM npm REQUIRED)' ""
      ''
      # use system boost instead of FetchContent.
      # FETCH_CONTENT_BOOST_USED prevents Simple-Web-Server from re-finding boost
      # substituteInPlace cmake/dependencies/Boost_Sunshine.cmake \
      #   --replace-fail 'set(BOOST_VERSION "1.89.0")' 'set(BOOST_VERSION "${boost.version}")'
      + ''
        echo 'set(FETCH_CONTENT_BOOST_USED TRUE)' >> cmake/dependencies/Boost_Sunshine.cmake
        substituteInPlace cmake/packaging/linux.cmake \
          --replace-fail 'find_package(Systemd)' "" \
          --replace-fail 'find_package(Udev)' ""

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

    nativeBuildInputs =
      [
        cmake
        pkg-config
        python3
        makeWrapper
        # linux
        wayland-scanner
        # Avoid fighting upstream's usage of vendored ffmpeg libraries
        autoPatchelfHook
      ]
      ++ lib.optionals cudaSupport [
        autoAddDriverRunpath
        cudaPackages.cuda_nvcc
        (lib.getDev cudaPackages.cuda_cudart)
      ];

    buildInputs =
      [
        boost
        libwebp
        xz
        icu
        libsysprof-capture
        lerc
        openssl
        nlohmann_json
        curl
        miniupnpc
        avahi
        libevdev
        libpulseaudio
        libX11
        libdeflate
        libxcb
        libXfixes
        libXrandr
        libXtst
        libXi
        libopus
        libdrm
        wayland
        libffi
        libcap
        pcre
        pcre2
        libuuid
        libselinux
        libsepol
        libthai
        libdatrie
        libXdmcp
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
        libnotify
        (
          if lib ? libappindicator
          then libappindicator
          else libappindicator-gtk3
        )
      ]
      ++ lib.optionals cudaSupport [
        cudaPackages.cudatoolkit
        cudaPackages.cuda_cudart
      ];

    runtimeDependencies =
      [
        avahi
        libgbm
        libXrandr
        libxcb
        libglvnd
      ]
      ++ lib.optionals cudaSupport [vulkan-loader];

    cmakeFlags =
      [
        "-Wno-dev"
        (lib.cmakeBool "BOOST_USE_STATIC" false)
        (lib.cmakeBool "BUILD_DOCS" false)
        (lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "nixpkgs")
        (lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://nixos.org")
        (lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/NixOS/nixpkgs/issues")
        (lib.cmakeFeature "BOOST_ROOT" "${boost}")
      ]
      ++ lib.optionals (!cudaSupport) [
        (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" false)
        # upstream tries to use systemd and udev packages to find these directories in FHS; set the paths explicitly instead
        (lib.cmakeBool "UDEV_FOUND" true)
        (lib.cmakeBool "SYSTEMD_FOUND" true)
        (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
        (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
        (lib.cmakeFeature "SYSTEMD_MODULES_LOAD_DIR" "lib/modules-load.d")
      ];

    env = {
      BUILD_VERSION = "${finalAttrs.version}";
      BRANCH = "master";
      COMMIT = "";
    };

    # copy webui where it can be picked up by build
    preBuild = ''
      cp -r ${finalAttrs.ui}/build ../
    '';

    buildFlags = [
      "sunshine"
    ];

    # allow Sunshine to find libvulkan
    postFixup = lib.optionalString cudaSupport ''
      wrapProgram $out/bin/sunshine \
        --set LD_LIBRARY_PATH ${lib.makeLibraryPath [vulkan-loader]}
    '';

    doInstallCheck = isLinux;

    nativeInstallCheckInputs = lib.optionals isLinux [udevCheckHook];
    # redefine installPhase to avoid attempt to build webui
    installPhase = ''
      runHook preInstall

      cmake --install .

      runHook postInstall
    '';

    postInstall = ''
      install -Dm644 ../packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
        $out/share/applications/${finalAttrs.pname}.desktop
    '';

    meta = with lib; {
      description = "Apollo is a Game stream host for Moonlight";
      homepage = "https://github.com/ClassicOldSong/Apollo";
      license = licenses.gpl3Only;
      mainProgram = "sunshine";
      maintainers = with maintainers; [zhuher];
      platforms = platforms.linux;
    };
  })
