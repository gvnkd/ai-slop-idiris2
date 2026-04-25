# Foreign Function Interface (FFI)

## Overview

The Idris 2 FFI calls functions in other languages. It is designed to be flexible across multiple code generators.

## `%foreign` Directive

```idris
%foreign "C:puts,libc"
puts : String -> PrimIO Int
```

Specifier format: `"Language:name,library"`

Multiple specifiers — the code generator chooses the one it understands:

```idris
%foreign "scheme,chez:foreign-alloc"
         "scheme,racket:malloc"
         "C:malloc,libc"
allocMem : (bytes : Int) -> PrimIO AnyPtr
```

## C FFI

### Pure Functions

```idris
%foreign "C:add,libsmall"
add : Int -> Int -> Int
```

### Side-Effecting Functions

Use `PrimIO` for effects:

```idris
%foreign "C:addWithMessage,libsmall"
prim__addWithMessage : String -> Int -> Int -> PrimIO Int

addWithMessage : HasIO io => String -> Int -> Int -> io Int
addWithMessage s x y = primIO $ prim__addWithMessage s x y
```

Convert `PrimIO` to `HasIO` using `primIO`:

```idris
primIO : HasIO io => PrimIO a -> io a
```

### Callbacks

```idris
%foreign (libsmall "applyFn")
prim__applyFn : String -> Int -> (String -> Int -> String) -> PrimIO String

applyFn : HasIO io =>
          String -> Int -> (String -> Int -> String) -> io String
applyFn c i f = primIO $ prim__applyFn c i f
```

### Structs

```idris
import System.FFI

Point : Type
Point = Struct "point" [("x", Int), ("y", Int)]

getField : Struct s fs -> (n : String) -> FieldType n ty fs => ty
setField : Struct s fs -> (n : String) -> FieldType n ty fs => ty -> IO ()
```

**Important:** `Struct` types must define **all** fields of the C struct.

### Finalisers

```idris
onCollect : Ptr t -> (Ptr t -> IO ()) -> IO (GCPtr t)
onCollectAny : AnyPtr -> (AnyPtr -> IO ()) -> IO GCAnyPtr
```

The runtime frees the pointer when garbage collected.

## JavaScript FFI

### Specifiers

| Specifier | Target |
|-----------|--------|
| `javascript:lambda:...` | Both browser and Node |
| `node:lambda:...` | Node.js only |
| `browser:lambda:...` | Browser only |
| `javascript:support:file.js` | Support files (bundled in) |

### Examples

```idris
%foreign "browser:lambda: x => console.log(x)"
prim__consoleLog : String -> PrimIO ()

consoleLog : HasIO io => String -> io ()
consoleLog x = primIO $ prim__consoleLog x
```

### DOM Interaction

```idris
data DomNode = MkNode AnyPtr

%foreign "browser:lambda: () => document.body"
prim__body : () -> PrimIO AnyPtr

body : HasIO io => io DomNode
body = map MkNode $ primIO $ prim__body ()
```

## Primitive FFI Types

### Argument Types

`Int`, `Char`, `Double`, `Bits8/16/32/64`, `String`, `Ptr t`, `AnyPtr`

### Return Types

All argument types plus `()` and `PrimIO t`

### String Handling

- Idris `String` = UTF-8
- C `char*` returned by a function is **copied** to Idris heap and **freed** immediately
- Use `Ptr String` for potentially `NULL` values
