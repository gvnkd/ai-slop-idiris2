# Modules and Namespaces

## Modules

An Idris program consists of modules. Each module has:

1. Optional `module` declaration
2. List of `import` statements
3. Declarations and definitions

```idris
module BTree

public export
data BTree a = Leaf
             | Node (BTree a) a (BTree a)

export
insert : Ord a => a -> BTree a -> BTree a
```

File `BTree.idr` must match module name `BTree`. Exception: `Main` can be in any file.

Module path must match directory structure: `module Foo.Bar.MyModule` → `Foo/Bar/MyModule.idr`.

## Export Modifiers

Visibility is per **namespace**, not per file.

| Modifier | Functions | Data Types | Interfaces |
|----------|-----------|------------|------------|
| `private` (default) | Not exported | Not exported | Not exported |
| `export` | Type exported | Type constructor exported | Interface name exported |
| `public export` | Type + definition exported | Type + constructors exported | Interface + methods + defaults exported |

Rules:
- `public export` definitions cannot reference `private` or `export` names
- `export` types cannot reference `private` names
- `public export` makes the definition part of the module's API (use sparingly)

### Renaming Imports

```idris
import Data.List as L
import public C   -- re-exports C's public names
```

## Explicit Namespaces

Overload names within the same module:

```idris
module Foo

namespace X
  export
  test : Int -> Int
  test x = x * 2

namespace Y
  export
  test : String -> String
  test x = x ++ x

-- Disambiguated by type:
test 3       -- 6 : Int
test "foo"   -- "foofoo" : String
```

Fully qualified names: `Foo.X.test`, `Foo.Y.test`.

## Parameterised Blocks (`parameters`)

Group functions sharing common arguments:

```idris
parameters (x : Nat) (y : Nat)
  addAll : Nat -> Nat
  addAll z = x + y + z

-- Type: addAll : Nat -> Nat -> Nat -> Nat
```

Parameters can include data declarations and implicit arguments:

```idris
parameters {0 m : Type -> Type} {auto mon : Monad m}

  utility : IO Nat
  program : IO ()
```
