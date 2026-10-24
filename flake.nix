{
  description = "OnTheSpot - music downloader";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (system: pkgs:
        let
          pyPkgs = pkgs.python3.pkgs;

          music-tag = pyPkgs.buildPythonPackage {
            pname = "music-tag";
            version = "0.4.3";
            pyproject = true;
            src = pkgs.fetchFromGitHub {
              owner = "KristoforMaynard";
              repo = "music-tag";
              rev = "0.4.3";
              hash = "sha256-8i6sLSv7wWOIXbdSfnLVTLRCyziJWehdTYrz5irLpdI=";
            };
            build-system = [ pyPkgs.setuptools ];
            dependencies = [ pyPkgs.mutagen ];
            doCheck = false;
          };

          librespot = pyPkgs.buildPythonPackage {
            pname = "librespot";
            version = "0.0.10";
            pyproject = true;
            src = pkgs.fetchFromGitHub {
              owner = "ots-downloader";
              repo = "librespot-python";
              rev = "a4229a5c9dcaa0e13baa7484d34be83e5046cfa7";
              hash = "sha256-I5tIS9aBgpHCU8Ft/kS3d9tb6ulj0+HLT1LRCsRrx2Q=";
            };
            build-system = [ pyPkgs.setuptools pyPkgs.wheel ];
            dependencies = with pyPkgs; [
              defusedxml
              protobuf
              pycryptodomex
              pyogg
              requests
              websocket-client
              zeroconf
            ];
            pythonRelaxDeps = true;
            doCheck = false;
          };

          pywidevine = pyPkgs.pywidevine.overridePythonAttrs (old: {
            dependencies = map
              (d: if (d.pname or "") == "protobuf" then pyPkgs.protobuf else d)
              (old.dependencies or [ ]);
            pythonRelaxDeps = [ "protobuf" ];
            dontCheckRuntimeDeps = true;
          });
        in
        {
          default = pyPkgs.buildPythonApplication {
            pname = "onthespot";
            version = "1.1.4";
            pyproject = true;
            src = self;

            build-system = [ pyPkgs.setuptools pyPkgs.wheel ];

            nativeBuildInputs = [ pkgs.qt6.wrapQtAppsHook ];
            buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtwayland ];

            dependencies = (with pyPkgs; [
              flask
              flask-login
              m3u8
              mutagen
              pillow
              pyqt6
              pyqt6-sip
              requests
              urllib3
              yt-dlp
            ]) ++ [ librespot music-tag pywidevine ];

            pythonRelaxDeps = true;
            dontCheckRuntimeDeps = true;

            dontWrapQtApps = true;

            makeWrapperArgs = [
              "--prefix" "PATH" ":" "${pkgs.lib.makeBinPath [ pkgs.ffmpeg ]}"
              "--set" "FFMPEG_PATH" "${pkgs.lib.getExe pkgs.ffmpeg}"
            ];

            preFixup = ''
              makeWrapperArgs+=("''${qtWrapperArgs[@]}")
            '';

            postInstall = ''
              install -Dm644 src/onthespot/resources/org.onthespot.OnTheSpot.desktop \
                -t $out/share/applications/
              install -Dm644 src/onthespot/resources/icons/onthespot.png \
                $out/share/icons/hicolor/256x256/apps/onthespot.png
            
              # point the launcher at the GUI entry point
              sed -i \
                -e 's|^Exec=.*|Exec=onthespot-gui|' \
                -e '/^TryExec=/d' \
                $out/share/applications/org.onthespot.OnTheSpot.desktop
            '';

            doCheck = false;

            meta = {
              description = "Qt based music downloader written in python";
              homepage = "https://github.com/ots-downloader/onthespot";
              license = pkgs.lib.licenses.gpl2Only;
              mainProgram = "onthespot-gui";
            };
          };
        });

      overlays.default = final: prev: {
        onthespot = self.packages.${final.stdenv.hostPlatform.system}.default;
      };

      apps = forAllSystems (system: pkgs: {
        default = { type = "app"; program = "${self.packages.${system}.default}/bin/onthespot-gui"; };
        web = { type = "app"; program = "${self.packages.${system}.default}/bin/onthespot-web"; };
        cli = { type = "app"; program = "${self.packages.${system}.default}/bin/onthespot-cli"; };
      });

      devShells = forAllSystems (system: pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
          packages = [ pkgs.ffmpeg ];
        };
      });
    };
}
