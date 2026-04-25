# Reference: Dot Syntax for Records

## Overview

`.field` is a **postfix projection operator** that binds tighter than function application.

## Lexical Structure

| Expression | Parsed As |
|------------|-----------|
| `.foo` | Name (record field) |
| `Foo.bar.baz` | Single namespaced identifier |
| `foo.bar.baz` | Three lexemes: `foo`, `.bar`, `.baz` |
| `.foo.bar.baz` | Three lexemes: `.foo`, `.bar`, `.baz` |
| `(Constructor).field` | Field access on constructor |

Module names must start with an uppercase letter.

## Desugaring Rules

```
(.field1 .field2 .field3)  =>  \x => .field3 (.field2 (.field1 x))
(expr .field1 .field2)     =>  (.field1 .field2) expr
```

## Record Elaboration

For every field `f` of record `R`:

- Projection `f` in namespace `R` (prefix form)
- Projection `.f` in namespace `R` (postfix form)

Toggle prefix projections:

```idris
%prefix_record_projections on   -- default
%prefix_record_projections off  -- only .field form
```

## Example

```idris
record Point where
  constructor MkPoint
  x : Double
  y : Double

-- Projections (with %prefix_record_projections on):
.x : Point -> Double
.y : Point -> Double
x  : Point -> Double
y  : Point -> Double

pt : Point
pt = MkPoint 4.2 6.6

-- Postfix access
pt.x           -- 4.2
pt .x          -- 4.2 (space before dot)

-- Nested access
rect.topLeft.x + rect.bottomRight.y

-- User-defined projections
(.squared) : Double -> Double
(.squared) x = x * x
pt.x.squared   -- 17.64

-- In map
map (.x) [MkPoint 1 2, MkPoint 3 4]  -- [1.0, 3.0]

-- Nested record update
{ topLeft.x := 3 } rect
{ topLeft.x $= (+1) } rect

-- Qualified names
Main.Point.(.x) pt
Point.(.x) pt
(.x) pt
.x pt

-- Haskell-style projections
Main.Point.x pt
Point.x pt
(x) pt
x pt
```

## Key Points

- `.field` is a name, can be used as a function argument
- `map (.x) xs` works because `.x` is a function
- Spaces before dots may cause parsing issues: `map .x xs` parses as `map.x xs`
- All module names in qualified access must start with uppercase
