# Types and Functions

## Primitive Types

| Type | Description |
|------|-------------|
| `Int` | Fixed-size integer |
| `Integer` | Arbitrary-precision integer |
| `Double` | Double-precision floating point |
| `Char` | Unicode character |
| `String` | UTF-8 string |
| `Ptr` | Foreign pointer |
| `Bool` | `True` or `False` |

## Data Type Declarations

```idris
data Nat = Z | S Nat          -- Natural numbers (unary)
data List a = Nil | (::) a (List a)  -- Polymorphic lists
```

- Data type names **cannot** begin with a lowercase letter (reserved for implicit arguments)
- Constructors conventionally begin with a capital letter
- Functions may begin with a capital letter

## Function Definitions

All functions require a **type declaration** (single `:`, not Haskell's `::`):

```idris
plus : Nat -> Nat -> Nat
plus Z     y = y
plus (S k) y = S (plus k y)
```

Functions are defined by **pattern matching**. Literal integers are overloaded via interfaces.

## `where` Clauses

Local functions defined in `where` blocks:

```idris
reverse : List a -> List a
reverse xs = revAcc [] xs
  where
    revAcc : List a -> List a -> List a
    revAcc acc [] = acc
    revAcc acc (x :: xs) = revAcc (x :: acc) xs
```

**Important:** Names visible in the outer scope are also in scope in the `where` clause. Local functions **require** a type declaration.

## Totality and Covering

By default, functions must be **covering** — all inputs must be handled:

```idris
fromMaybe : Maybe a -> a
fromMaybe (Just x) = x
-- Error: not covering. Missing case: fromMaybe Nothing
```

Override with `partial`:

```idris
partial fromMaybe : Maybe a -> a
fromMaybe (Just x) = x
```

## Holes

Holes (`?name`) stand for incomplete code and help incremental development:

```idris
main : IO ()
main = putStrLn ?greeting

-- :t greeting  =>  greeting : String
```

Holes show the expected type and all variables in scope.

## Dependent Types

### First-Class Types

Types can be computed and used as values:

```idris
isSingleton : Bool -> Type
isSingleton True  = Nat
isSingleton False = List Nat

mkSingle : (x : Bool) -> isSingleton x
mkSingle True  = 0
mkSingle False = []
```

### Vectors (Dependent Lists)

```idris
data Vect : Nat -> Type -> Type where
   Nil  : Vect Z a
   (::) : a -> Vect k a -> Vect (S k) a
```

```idris
(++) : Vect n a -> Vect m a -> Vect (n + m) a
(++) Nil       ys = ys
(++) (x :: xs) ys = x :: xs ++ ys
```

The type guarantees the result length is `n + m`. A wrong definition is rejected by the type checker.

### Finite Sets (`Fin`)

```idris
data Fin : Nat -> Type where
   FZ : Fin (S k)
   FS : Fin k -> Fin (S k)
```

`Fin n` represents integers in range `[0, n)`. Used for bounds-safe indexing:

```idris
index : Fin n -> Vect n a -> a
index FZ     (x :: xs) = x
index (FS k) (x :: xs) = index k xs
```

No runtime bounds check needed — the type checker guarantees safety.

### Implicit Arguments

Names beginning with lowercase letters in types are **implicitly bound**:

```idris
index : Fin n -> Vect n a -> a
-- equivalent to:
index : forall a, n . Fin n -> Vect n a -> a
```

Explicit implicit arguments use braces:

```idris
index {a = Int} {n = 2} FZ (2 :: 3 :: Nil)
```

Implicit argument names are in scope in the function body.

## I/O and Do-Notation

```idris
data IO a  -- describes I/O operations

greet : IO ()
greet = do putStr "What is your name? "
           name <- getLine
           putStrLn ("Hello " ++ name)
```

- `x <- ioval` extracts the value from an `IO` action
- `pure : a -> IO a` injects a value into `IO`

## Laziness

Eager evaluation is the default. Use `Lazy` to suspend evaluation:

```idris
ifThenElse : Bool -> Lazy a -> Lazy a -> a
ifThenElse True  t e = t
ifThenElse False t e = e
```

## Infinite Data (Codata)

```idris
data Stream : Type -> Type where
  (::) : (e : a) -> Inf (Stream a) -> Stream a

ones : Stream Nat
ones = 1 :: ones
```

`Inf` marks recursive arguments as potentially infinite.

## Useful Data Types

### Maybe

```idris
data Maybe a = Just a | Nothing

maybe : Lazy b -> Lazy (a -> b) -> Maybe a -> b
```

### Tuples

```idris
fred : (String, Int)
fred = ("Fred", 42)
```

### Dependent Pairs (Sigma Types)

```idris
vec : (n : Nat ** Vect n Int)
vec = (2 ** [3, 4])

-- or using MkDPair:
vec : DPair Nat (\n => Vect n Int)
vec = MkDPair 2 [3, 4]
```

### Records

```idris
record Person where
    constructor MkPerson
    firstName, middleName, lastName : String
    age : Int

fred : Person
fred = MkPerson "Fred" "Joe" "Bloggs" 30

-- Field access
fred.firstName     -- "Fred"
age fred           -- 30

-- Record update
{ firstName := "Jim" } fred
{ age $= (+ 1) } fred
```

### Dependent Records

```idris
record SizedClass (size : Nat) where
    constructor SizedClassInfo
    students : Vect size Person
    className : String
```

Parameters appear as arguments to the type and cannot be updated.

## `let` Bindings

```idris
mirror : List a -> List a
mirror xs = let xs' = reverse xs in xs ++ xs'

-- Pattern matching in let
showPerson : Person -> String
showPerson p = let MkPerson name age = p in
                   name ++ " is " ++ show age ++ " years old"

-- Local function definitions
foldMap : Monoid m => (a -> m) -> Vect n a -> m
foldMap f = let fo : m -> a -> m
                fo ac el = ac <+> f el
             in foldl fo neutral
```

Use `:=` to avoid ambiguity with propositional equality.

## List Comprehensions

```idris
pythag : Int -> List (Int, Int, Int)
pythag n = [ (x, y, z) | z <- [1..n], y <- [1..z], x <- [1..y],
                          x*x + y*y == z*z ]
```

## Case Expressions

```idris
lookup_default : Nat -> List a -> a -> a
lookup_default i xs def = case list_lookup i xs of
                              Nothing => def
                              Just x  => x
```
