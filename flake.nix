{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-compat, flake-utils }:
    let
      ton = { host, pkgs ? host, stdenv ? pkgs.stdenv, staticGlibc ? false
        , staticMusl ? false, staticExternalDeps ? staticGlibc }:
        with host.lib;
        stdenv.mkDerivation {
          pname = "ton";
          version = "dev";

          src = ./.;

          nativeBuildInputs = with host;
            [ cmake ninja pkg-config git ] ++ [ dpkg rpm createrepo_c ];
          buildInputs = with pkgs;
          # at some point nixpkgs' pkgsStatic will build with static glibc
          # then we can skip these manual overrides
          # and switch between pkgsStatic and pkgsStatic.pkgsMusl for static glibc and musl builds
            if !staticExternalDeps then [
              openssl
              zlib
              libmicrohttpd
            ] else
              [
                (openssl.override { static = true; }).dev
                (zlib.override { shared = false; }).dev
                pkgsStatic.libmicrohttpd.dev
              ] ++ optional staticGlibc glibc.static;

          cmakeFlags = [ "-DTON_USE_ABSEIL=OFF" ] ++ optionals staticMusl [
            "-DCMAKE_CROSSCOMPILING=OFF" # pkgsStatic sets cross
          ] ++ optionals (staticGlibc || staticMusl) [
            "-DCMAKE_LINK_SEARCH_START_STATIC=ON"
            "-DCMAKE_LINK_SEARCH_END_STATIC=ON"
          ];

          LDFLAGS =
            optional staticExternalDeps "-static-libgcc -static-libstdc++";

          postInstall = ''
            moveToOutput bin "$bin"
          '';

          outputs = [ "bin" "out" ];
        };
    in with flake-utils.lib;
    eachSystem (with system; [ x86_64-linux x86_64-darwin aarch64-linux aarch64-darwin ]) (system:
      let host = nixpkgs.legacyPackages.${system};
      in { defaultPackage = ton { inherit host; }; })
    // (let host = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages = rec {
        #test = host.mkShell { nativeBuildInputs = [ host.cmake ]; };
        x86_64-linux-static.ton = ton {
          inherit host;
          stdenv = host.makeStatic host.stdenv;
          staticGlibc = true;
        };
        x86_64-linux-musl.ton = ton {
          inherit host;
          pkgs = nixpkgs.legacyPackages.x86_64-linux.pkgsStatic;
          staticMusl = true;
        };
        x86_64-linux-oldglibc.ton = (let
          # look out for https://github.com/NixOS/nixpkgs/issues/129595 for progress on better infra for this
          #
          # nixos 19.09 ships with glibc 2.27
          # we could also just override glibc source to a particular release
          # but then we'd need to port patches as well
          nixos1909 = (import (builtins.fetchTarball {
            url = "https://channels.nixos.org/nixos-19.09/nixexprs.tar.xz";
            sha256 = "1vp1h2gkkrckp8dzkqnpcc6xx5lph5d2z46sg2cwzccpr8ay58zy";
          }) { localSystem = "x86_64-linux"; });
          glibc227 = nixos1909.glibc // { pname = "glibc"; };
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [
              # XXX
              # https://github.com/NixOS/nixpkgs/issues/174236
              (self: super: {
                glibc = glibc227;
                glibcLocales = nixos1909.glibcLocales;
                glibcIconv = nixos1909.glibcIconv;
                stdenv = super.stdenv // {
                  overrides = self2: super2:
                    super.stdenv.overrides self2 super2 // {
                      glibc = glibc227;
                      linuxHeaders = builtins.head glibc227.buildInputs;
                    };
                };
              })
            ];
          };
        in ton {
          inherit host;
          inherit pkgs;
          staticExternalDeps = true;
        });
        x86_64-linux-oldglibc_staticbinaries = host.symlinkJoin {
          name = "ton";
          paths = [ x86_64-linux-musl.ton.bin x86_64-linux-oldglibc.ton.out ];
        };
      };
    });
}