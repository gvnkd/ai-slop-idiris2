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
    idris2-linux-src = { url = "github:stefan-hoeck/idris2-linux"; flake = false; };
    idris2-cptr-src = { url = "github:stefan-hoeck/idris2-cptr"; flake = false; };
    idris2-elin-src = { url = "github:stefan-hoeck/idris2-elin"; flake = false; };
    idris2-finite-src = { url = "github:stefan-hoeck/idris2-finite"; flake = false; };
    #idris2-async-src = { url = "github:stefan-hoeck/idris2-async?ref=ce1764384fcf024c135ae97d97894c696c31f505"; flake = false; };
    idris2-async-src = { url = "github:stefan-hoeck/idris2-async"; flake = false; };
    idris2-containers-src = { url = "github:idris-community/idris2-containers"; flake = false; };
    idris2-hashable-src = { url = "github:Z-snails/idris2-hashable"; flake = false; };
    idris2-streams-src = { url = "github:stefan-hoeck/idris2-streams"; flake = false; };
    idris2-filepath-src = { url = "github:stefan-hoeck/idris2-filepath"; flake = false; };
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
      idris2-linux-src,
      idris2-cptr-src,
      idris2-elin-src,
      idris2-finite-src,
      idris2-async-src,
      idris2-containers-src,
      idris2-hashable-src,
      idris2-streams-src,
      idris2-filepath-src,
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
            mkdir $out/lib
            find ./ -type f -name '*.so' -exec cp {} $out/lib/ \;
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
        elin = buildIdris { pname = "elin"; src = idris2-elin-src; deps = [ quantifiers-extra ref1 ]; };
        cptr = buildIdris { pname = "cptr"; src = idris2-cptr-src; deps = [ elin quantifiers-extra ref1 array algebra ]; };
        finite = buildIdris { pname = "finite"; src = idris2-finite-src; deps = [ elab-util ]; };
        async = buildIdris { pname = "async"; src = idris2-async-src; deps = [ array algebra ref1 containers elab-util elin quantifiers-extra hashable ]; };
        async-epoll = buildIdris { pname = "async-epoll"; ipkgs = "async-epoll/async-epoll"; src = idris2-async-src; deps = [ hashable linux async async-posix posix bytestring cptr ansi finite array algebra ref1 containers elab-util elin quantifiers-extra ]; };
        async-posix = buildIdris { pname = "async-posix"; ipkgs = "async-posix/async-posix"; src = idris2-async-src; deps = [ hashable async posix array bytestring cptr finite ansi algebra ref1 containers elab-util elin quantifiers-extra ]; };
        containers = buildIdris { pname = "containers"; src = idris2-containers-src; deps = [ elab-util array algebra ref1 hashable ]; };
        hashable = buildIdris { pname = "hashable"; src = idris2-hashable-src; deps = [ ]; };
        posix = buildIdris { pname = "posix"; ipkgs = "posix/posix"; src = idris2-linux-src; deps = [ bytestring algebra array ref1 cptr elin quantifiers-extra elab-util finite ]; };
        linux = buildIdris { pname = "linux"; ipkgs = "linux/linux"; src = idris2-linux-src; deps = [ posix bytestring algebra array ref1 cptr elin quantifiers-extra elab-util finite ]; };
        filepath = buildIdris { pname = "filepath"; ipkgs = "filepath"; src = idris2-filepath-src; deps = [ hashable async containers posix bytestring algebra array ref1 cptr elin quantifiers-extra elab-util finite ]; };
        streams = buildIdris { pname = "streams"; ipkgs = "streams"; src = idris2-streams-src; deps = [ hashable async containers posix bytestring algebra array ref1 cptr elin quantifiers-extra elab-util finite ]; };
        streams-posix = buildIdris { pname = "streams-posix"; ipkgs = "posix/streams-posix"; src = idris2-streams-src; deps = [ filepath ansi async-posix hashable streams containers async posix bytestring algebra array ref1 cptr elin quantifiers-extra elab-util finite ]; };
        tui = buildIdris { 
          pname = "tui"; 
          src = idris2-tui-src; 
          deps = [ ansi elab-util json parser bytestring algebra array ref1 ilex-core ilex-json ilex refined quantifiers-extra ]; 
        };
        tui-async = buildIdris { 
          pname = "tui-async/tui-async"; 
          src = idris2-tui-src; 
          deps = [ hashable async-posix linux ansi elab-util json parser bytestring algebra array ref1 ilex-core ilex-json ilex refined quantifiers-extra tui posix cptr elin finite async containers async-epoll ]; 
        };

      in {
        devShells.default = pkgs.mkShell rec {
          nativeBuildInputs = [ idris2 ];
          buildInputs = [
            pkgs.python3
            tui
            tui-async
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
            posix linux cptr async async-epoll async-posix containers elin finite
            hashable
            streams
            streams-posix
            filepath
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

