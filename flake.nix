{
  description = "Ansible Parallel Monitor TUI (Standard Env Vars Mode)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    idris2-tui-src = { url = "github:emdash/idris2-tui"; flake = false; };
    idris2-ansi-src = { url = "github:idris-community/idris2-ansi"; flake = false; };
    idris2-elab-util-src = { url = "github:stefan-hoeck/idris2-elab-util"; flake = false; };
    idris2-json-src = { url = "github:stefan-hoeck/idris2-json"; flake = false; };
    idris2-parser-src = { url = "github:stefan-hoeck/idris2-parser"; flake = false; };
    idris2-ilex-src = { url = "github:stefan-hoeck/idris2-ilex"; flake = false; };
    idris2-bytestring-src = { url = "github:stefan-hoeck/idris2-bytestring"; flake = false; };
    idris2-algebra-src = { url = "github:stefan-hoeck/idris2-algebra"; flake = false; };
    idris2-array-src = { url = "github:stefan-hoeck/idris2-array"; flake = false; };
    idris2-ref1-src = { url = "github:stefan-hoeck/idris2-ref1"; flake = false; };
    idris2-refined-src = { url = "github:stefan-hoeck/idris2-refined"; flake = false; };
    idris2-quantifiers-extra-src = { url = "github:stefan-hoeck/idris2-quantifiers-extra"; flake = false; };
  };

  outputs = { self, nixpkgs, flake-utils,
      idris2-tui-src,
      idris2-ansi-src,
      idris2-elab-util-src,
      idris2-json-src,
      idris2-parser-src,
      idris2-ilex-src,
      idris2-bytestring-src,
      idris2-algebra-src,
      idris2-array-src,
      idris2-ref1-src,
      idris2-refined-src,
      idris2-quantifiers-extra-src,
    }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        idris2 = pkgs.idris2;
        ver = idris2.version;
        
        buildIdris = { pname, ipkgs ? pname, src, deps ? [] }: pkgs.stdenv.mkDerivation {
          inherit pname src;
          version = "main";
          nativeBuildInputs = [ idris2 ];

          buildPhase = ''
            export IDRIS2_PACKAGE_PATH="${pkgs.lib.makeSearchPath "idris2-${ver}" deps}"
            export IPKG=${ipkgs}.ipkg;
            idris2 --build "$IPKG"
          '';

          installPhase = ''
            mkdir -p $out
            # Устанавливаем IDRIS2_PREFIX, чтобы install не лез в системные пути
            export IDRIS2_PREFIX=$out
            idris2 --install "$IPKG"
            if [[ -d ./lib ]]; then
              mkdir $out/lib
              cp ./lib/*.so $out/lib/
            fi
          '';
        };

        # Цепочка зависимостей
        quantifiers-extra = buildIdris { pname = "quantifiers-extra"; src = idris2-quantifiers-extra-src; deps = [ ]; };
        refined = buildIdris { pname = "refined"; src = idris2-refined-src; deps = [ elab-util algebra ]; };
        ref1 = buildIdris { pname = "ref1"; src = idris2-ref1-src; deps = [ ]; };
        array = buildIdris { pname = "array"; src = idris2-array-src; deps = [ algebra ref1 ]; };
        algebra = buildIdris { pname = "algebra"; src = idris2-algebra-src; };
        bytestring = buildIdris { pname = "bytestring"; ipkgs = "bytestring"; src = idris2-bytestring-src; deps = [ algebra array ref1 ]; };
        ilex = buildIdris { pname = "ilex"; ipkgs = "ilex"; src = idris2-ilex-src; deps = [ elab-util bytestring algebra array ref1 ilex-core refined ]; };
        ilex-core = buildIdris { pname = "ilex-core"; ipkgs = "core/ilex-core"; src = idris2-ilex-src; deps = [ elab-util bytestring algebra array ref1 ]; };
        ilex-json = buildIdris { pname = "ilex-json"; ipkgs = "json/ilex-json"; src = idris2-ilex-src; deps = [ elab-util bytestring algebra array ref1 ilex ilex-core refined ]; };
        parser = buildIdris { pname = "parser"; src = idris2-parser-src; deps = [ elab-util ilex-core bytestring algebra array ref1 ]; };
        json = buildIdris { pname = "json"; src = idris2-json-src; deps = [ parser elab-util ilex-core ilex-json bytestring algebra array ref1 ilex refined ]; };
        ansi = buildIdris { pname = "ansi"; src = idris2-ansi-src; };
        elab-util = buildIdris { pname = "elab-util"; ipkgs = "elab-util"; src = idris2-elab-util-src; };
        tui = buildIdris { 
          pname = "tui"; 
          src = idris2-tui-src; 
          deps = [ ansi elab-util json parser bytestring algebra array ref1 ilex-core ilex-json ilex refined quantifiers-extra ]; 
        };

      in {
        devShells.default = pkgs.mkShell rec {
          nativeBuildInputs = [ idris2 ];
          buildInputs = [
            tui
            elab-util
            json
            parser
            bytestring
            algebra
            array
            ref1
            ilex-core
            ilex-json
            ilex
            refined
            ansi
            quantifiers-extra
          ];
          shellHook = ''
            export IDRIS2_PACKAGE_PATH="${pkgs.lib.makeSearchPath "idris2-${ver}" buildInputs }"
            export LD_LIBRARY_PATH="${pkgs.lib.makeSearchPath "lib" buildInputs }"
            export IDRIS2_LIBS="${idris2}/lib"
            export IDRIS2_DATA="${idris2}/share/idris2-${ver}"
            echo "idris2 --build ansible_mon.ipkg"
          '';
        };

        packages.default = pkgs.stdenv.mkDerivation {
          pname = "ansible-mon";
          src = ./.;
          nativeBuildInputs = [ idris2 ];
          IDRIS2_PACKAGE_PATH = pkgs.lib.makeSearchPath "lib" [ ansi elab-util tui ];

          buildPhase = "idris2 --build ansible_mon.ipkg";
          installPhase = "mkdir -p $out/bin && cp build/exec/mon $out/bin/ansible-mon";
        };
      });
}

