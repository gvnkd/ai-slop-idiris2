# Reference: Documenting Code

## Two Forms of Documentation

| Form | Purpose | Compiler |
|------|---------|----------|
| Comments | Reader explanation | Ignored |
| Inline docs | API documentation | Parsed and stored |

## Comments

Same as Haskell:

```idris
-- Single line comment

{-
  Multi-line comment
  spans multiple lines
-}
```

## Inline Documentation

Uses `|||` (three pipes) at the start of each line.

### Overview

The first paragraph is the **overview** (shown in summaries):

```idris
||| Add some numbers.
|||
||| Addition is really great. This paragraph is not part of the overview.
|||
||| You can even provide examples:
||| ```idris example
||| add 4 5
||| ```
|||
||| Lists are also nifty:
||| * Really nifty!
||| * Yep!
||| @ n is the recursive param
||| @ m is not
add : (n, m : Nat) -> Nat
add Z     m = m
add (S n) m = S (add n m)
```

### Parameter Annotations

`@ name Description` annotates named parameters:

```idris
||| @ a the contents of the vectors
||| @ xs the first vector (recursive param)
||| @ ys the second vector (not analysed)
appendV : (xs : Vect n a) -> (ys : Vect m a) -> Vect (add n m) a
```

### Constructor Documentation

```idris
data Ty =
  ||| Unit
  UNIT |
  ||| Functions
  ARR Ty Ty
```

### Record Documentation

```idris
||| A yummy food record
record Yummy where
  ||| Make a yummy
  constructor MkYummy
  ||| What to eat
  food : String
```

### Module Documentation

```idris
||| This module provides data processing utilities.
module Docs
```

## Viewing Documentation

| Environment | Command |
|-------------|---------|
| REPL | `:doc name` |
| Emacs | `C-c C-d` |
| Vim | `<LocalLeader>h` |

## Markdown Support

Documentation is written in Markdown, but not all contexts display all formatting:
- Images not displayed in REPL
- Some terminals may not render italics correctly
- Code blocks with `idris` language tag are rendered as examples
