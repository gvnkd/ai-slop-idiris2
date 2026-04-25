# Structuring Applications (Control.App)

## The `App` Type

`App` is like `IO` but with exceptions and state management:

```idris
data App : {default MayThrow l : Path} ->
           (es : List Error) -> Type -> Type
```

| Parameter | Description |
|-----------|-------------|
| `Path` | `NoThrow` or `MayThrow` (default: `MayThrow`) |
| `es` | List of error types that can be thrown |

## Basic Usage

```idris
import Control.App
import Control.App.Console

hello : Console es => App es ()
hello = putStrLn "Hello, App world!"

main : IO ()
main = run hello
```

## Interfaces

Interfaces constrain allowed operations:

```idris
interface Console e where
  putChar : Char -> App {l} e ()
  putStr  : String -> App {l} e ()
  getChar : App {l} e Char
  getLine : App {l} e String
```

Combine multiple interfaces with `Has`:

```idris
helloCount : Has [Console, State Counter Int] es => App es ()
```

`Has` computes constraints:

```idris
0 Has : List (a -> Type) -> a -> Type
Has [] es = ()
Has (e :: es') es = (e es, Has es' es)
```

## Exceptions

```idris
throw : HasErr err es => err -> App es a
catch : HasErr err es => App es a -> (err -> App es a) -> App es a

handle : App (err :: e) a ->
         (onok : a -> App e b) ->
         (onerr : err -> App e b) -> App e b
```

## State

```idris
data State : (tag : a) -> Type -> List Error -> Type

get : (0 tag : _) -> State tag t e => App {l} e t
put : (0 tag : _) -> State tag t e => (1 val : t) -> App {l} e ()

new : t -> (1 p : State tag t e => App {l} e a) -> App {l} e a
```

Tags distinguish different states (erased at runtime).

## `Path` and Linearity

`Path` tracks whether code can throw exceptions, enabling safe linear resource usage:

```idris
data Path = MayThrow | NoThrow

(>>=) : SafeBind l l' =>
        App {l} e a -> (a -> App {l=l'} e b) -> App {l=l'} e b
```

Safe bind transitions: `SafeSame` (no change) or `SafeToThrow` (`NoThrow` → `MayThrow`).

## Linear Bind

```idris
bindL : App {l=NoThrow} e a ->
        (1 k : a -> App {l} e b) -> App {l} e b
```

Guarantees the continuation runs exactly once — required for linear resources.

## `App1` for Linear Interfaces

For programs that exclusively use linear resources (never throw):

```idris
data App1 : {default One u : Usage} ->
            (es : List Error) -> Type -> Type

data Usage = One | Any
```

Convert between `App` and `App1`:

```idris
app    : (1 p : App {l=NoThrow} e a) -> App1 {u=Any} e a
app1   : (1 p : App1 {u=Any} e a) -> App {l} e a
```

## Running Programs

```idris
Init : List Error
Init = [AppHasIO]

run : App {l} Init a -> IO a
```

Top-level programs are wrapped in `handle` to deal with exceptions.
