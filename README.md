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

## Task Logging

When a task in `tasks.json` has a `logFile` field defined, all task output is streamed to that file:

- Log begins with `[START] YYYY-MM-DD HH:MM:SS`
- Raw output is written through `tee` (ANSI escape sequences preserved as-is)
- Log ends with `[END] YYYY-MM-DD HH:MM:SS STATUS` (SUCCESS or FAILED)

Example in `tasks.json`:
```json
{
  "name": "My Task",
  "path": "ls",
  "args": ["-la", "/"],
  "timeout": 10,
  "logFile": "logs/my_task.log"
}
```

# C FFI Helpers

Custom C code lives in `src/cstr_write.c` and is compiled to `cstr_write.so`:
```sh
gcc -shared -fPIC -o cstr_write.so src/cstr_write.c
cp cstr_write.so build/exec/amon_app/
```

