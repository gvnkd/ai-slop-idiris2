# Idris2 Style Guide

Adapted from [stefan-hoeck/idris2-style-guide](https://github.com/stefan-hoeck/idris2-style-guide).

## Formatting

- **80 char line limit.** Long expressions split onto next line, indented 2 spaces.
- **2 spaces, no tabs.**
- **Blank lines** between top-level definitions only. No blank line between signature and implementation.

## Alignment

Align arrows in `case`/`do` blocks, colons in data declarations, equals in function implementations, record fields, and list values when it aids readability.

```idris
nucleobase : String -> Maybe String
nucleobase s =
  case toLower s of
    "adenine"  => Just "A"
    "guanine"  => Just "G"
    "cytosine" => Just "C"
    _          => Nothing
```

## Data Declarations

- Prefer `record` over single-constructor `data`.
- Use GADT-style for everything except plain enumerations:

```idris
data Error : Type -> Type where
  Custom     : (err : e) -> Error e
  EndOfInput : Error e
```

Plain enums are fine:

```idris
data YesNo = Yes | No
```

## List Declarations

Start values on new line, each on its own line:

```idris
fibonacci : List Nat
fibonacci =
  [ 1
  , 1
  , 2
  , 3
  , 5
  ]
```

## Case Expressions

Start `case` on new line, indented 2 spaces. If RHS is too long, continue on next line indented 2 spaces.

```idris
orderNr : String -> Maybe Nat
orderNr s =
  case toLower s of
    "h"  => Just 1
    "he" => Just 2
    _    => Nothing
```

## Let Expressions

Use `:=` (not `=`). Indent `let` by 2, `in` by 3:

```idris
addSquares : Num a => (x,y : a) -> a
addSquares x y =
  let sx := x * x
      sy := y * y
   in sx + sy
```

## Where Blocks

Place `where` on its own line, indented 2 spaces. Consider blank line before `where`:

```idris
sumSquares : Num a => List a -> a
sumSquares = foldl acc 0

  where
    acc : a -> a -> a
    acc sum v = sum + v * v
```

## Function Declarations

- Prefer **named arguments**, especially multiple args of same type:

```idris
login : (name, password : String) -> Bool
```

- Multi-line declarations: align `->` and arguments:

```idris
lengthyFunctionDecl:
     (arg1       : String)
  -> (anotherArg : Nat)
  -> Either String (List Nat)
```

- Auto-implicit args in multi-line declarations: use `{auto _ : Foo}` syntax (not `=>`):

```idris
programm:
     {auto _   : HasIO io}
  -> (numLines : Nat)
  -> io (Either String (List t))
```

## Function Application

Long applications: each argument on its own line, indented 2 spaces. Prefer named arguments in applications:

```idris
me : Person
me =
  MkPerson
    { name    = "Stefan Höck"
    , age     = 45
    , hobbies = [ "hiking" ]
    }
```

## Idiom Brackets

Closing `|]` on its own line if expression exceeds line limit:

```idris
maybeMe : Maybe Person
maybeMe =
  [| MkPerson
       nameM
       ageM
       (Just ["hiking"])
  |]
```

## Do Blocks

Always start `do` on new line, `do` is last token on previous line:

```idris
myProg : IO ()
myProg = do
  putStr "Enter number: "
  s <- map trim getLine
```

## Comments

- **Document all exported** top-level functions, interfaces, and data types. This is the most important rule.

## Mutually Recursive Functions

Avoid `mutual` blocks. Declare signatures first, then definitions:

```idris
even : Nat -> Bool

odd : Nat -> Bool

even 0     = True
even (S k) = not (odd k)

odd 0     = False
odd (S k) = not (even k)
```

## Parameters Blocks

Use `parameters` for read-only shared args (especially auto-implicit deps). Prefer over `ReaderT`:

```idris
parameters {auto conf : Config}
           {auto log  : Logger}

  utility : IO Nat
  program : IO ()
```

## Interfaces

- Think twice before defining your own interface. Idris supports overloaded function names without interfaces.
- Interface resolution is proof search — many Haskell type class patterns are more naturally written with predicates in Idris.
- Interfaces are first-class: implementations can be passed explicitly:

```idris
myEq : Eq Bool
myEq = MkEq (\_,_ => False) (\_,_ => True)

test : Bool -> Bool -> Bool
test = (==) @{myEq}
```
