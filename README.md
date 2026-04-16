# Overview
This is a playgroud to check if an AI is able to generate a code in Idris2.

# Build and Run
To build this project you need to use a nix package manager.
```sh
direnv allow
idris2 --build amon.ipkg
./build/exec/amon
```

## Build a playground examples
Playground examples are a code snippets to reveal an ability of AI to generate a code using various Idris2 subsystems.
```sh
idris2 pg/Main.idr -o pg
./build/exec/pg
```
