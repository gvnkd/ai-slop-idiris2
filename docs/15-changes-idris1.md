# Changes Since Idris 1

## Core Language: Quantities in Types

Idris 2 uses **Quantitative Type Theory (QTT)**. Every variable has a quantity:

| Quantity | Meaning |
|----------|---------|
| `0` | Erased at runtime |
| `1` | Used exactly once |
| *(none)* | Unrestricted (Idris 1 behavior) |

This is the **biggest breaking change** when converting Idris 1 programs.

### Erasure

Implicit arguments (lowercase names in types) have quantity `0` by default:

```idris
-- Idris 1: works (n inferred as needed)
vlen : Vect n a -> Nat
vlen {n} xs = n

-- Idris 2: n has quantity 0, cannot return it
vlen : Vect n a -> Nat
vlen xs = n  -- Error: n is erased

-- Fix: make n unrestricted
vlen : {n : Nat} -> Vect n a -> Nat
vlen xs = n
```

**Rule:** Pattern matching on `0`-multiplicity arguments is an error (unless value is inferrable).

### Linearity

New `1` multiplicity for exact-once usage — enables resource protocols.

## Prelude and Base Libraries

The Prelude is smaller in Idris 2. Many functions moved to `base` libraries:

| Moved From | Moved To |
|------------|----------|
| `Data.List` functions | `Data.List`, `Data.Nat` |
| `Data.Maybe` functions | `Data.Maybe`, `Data.Either` |
| File management | `System.File`, `System.Directory` |
| `Decidable.Equality` | Separate module |

## Smaller Changes

### Ambiguous Name Resolution

- Idris 2 simplifies disambiguation (less backtracking)
- May require more explicit annotations
- Default ambiguity depth: 3 (`%ambiguity_depth 10` to change)
- Concrete return types or argument types resolve names
- Interface method vs. concrete function: concrete wins

### Modules and Export

- Visibility rules apply per **namespace**, not per **file**
- Module names must match filenames (except `Main`)

### `%language` Pragmas

All Idris 1 `%language` pragmas removed. Extensions may be added in the future.

`%access` pragma removed — use visibility modifiers on declarations.

### `let` Bindings

```idris
-- Idris 1: x reduces to val during type checking
let x = val in e

-- Idris 2: equivalent to (\x => e) val
-- No computational behavior guaranteed
```

Use local function definitions instead of `let` when reduction is needed.

Alternative syntax: `let x := val in e`

### `auto`-Implicits and Interfaces

Now use the **same mechanism**:

```idris
-- These are equivalent:
fromMaybe : (x : Maybe a) -> {auto p : IsJust x} -> a
fromMaybe : (x : Maybe a) -> IsJust x => a
```

The constraint arrow `=>` means auto-implicit search.

Search hints:

```idris
data Elem : (x : a) -> (xs : List a) -> Type where
     [search x]
     Here : Elem x (x :: xs)
     There : Elem x xs -> Elem x (y :: xs)

%hint showBool : MyShow Bool
```

### Record Fields

Dot notation for field access:

```idris
fred.firstName   -- new
firstName fred   -- still works
```

### Totality and Coverage

- `%default covering` is the **default** (was `%default partial` in Idris 1)
- Use `partial` annotation instead of changing the default globally

### Build Artefacts

- Checked modules: `build/ttc/` (was in different locations)
- Executables: `build/exec/`

### Packages

- `depends` field replaces `pkgs`
- String fields (URLs, etc.) must use double quotes

## New Features

### Local Function Definitions

```idris
chat : IO ()
chat = do
  x <- getLine
  let greet : String -> String
      greet msg = msg ++ " " ++ x
  putStrLn (greet "Hello")
```

`where` blocks are elaborated via `let`. No type inference for `where` functions.

### Implicit Argument Scope

Names in types are in scope in the function body (including `where` blocks):

```idris
showVect : Show a => Vect n a -> String
showVect xs = "[" ++ showBody xs ++ "]"
  where
    showBody : forall n . Vect n a -> String  -- need explicit forall
```

### Named Implicit Arguments

```idris
MkDog {name = "Max", age = 3}
MkFour {x, y, _}   -- skip unnamed args
f {}                -- skip all named args
```

### Better Inference

Holes are **global** (not local to expression):

```idris
test : Vect ? Int
test = [1, 2, 3, 4]
-- :t test => Vect (S (S (S (S Z)))) Int
```

`?` leaves a hole; `_` binds as implicit.

### Dependent Case

```idris
append : Vect n a -> Vect m a -> Vect (n + m) a
append xs ys = case xs of
                   []      => ys
                   (x :: xs) => x :: append xs ys
```

Original implicit arguments remain available in case bodies.

### Record Updates

```idris
{ firstName := "Jim" } fred
{ age $= (+ 1) } fred

-- Nested:
{ topLeft.x := 3 } rect
```

### Generate Definition

`:gd 3 append` generates a full definition from a type signature.

### Chez Scheme Target

Default code generator. Faster than Idris 1's C backend.
