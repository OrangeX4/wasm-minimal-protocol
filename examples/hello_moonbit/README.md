# MoonBit wasm plugin example

This is a bare-bones Typst plugin, written in [MoonBit](https://www.moonbitlang.com/).

## Compile

To compile this example, you need the [MoonBit toolchain](https://www.moonbitlang.com/download/). Install it with:

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

After installing, `moon` should be available on your PATH. Then, build the project for the `wasm` (linear-memory) target:

```sh
moon build --target wasm --release
cp _build/wasm/release/build/hello.wasm .
```

## Build with Typst

Simply run `typst compile hello.typ`, and observe that it works!

## Notes on the implementation

### Protocol FFI

MoonBit's `wasm` target uses linear memory. For FFI imports, only **primitive types** (`Int`, `UInt`, `Int64`, `Float`, `Double`, `Bool`) are accepted as parameter types — using `FixedArray[Byte]` directly in `fn = "module" "func"` declarations is a compile error ([4042] Invalid stub type).

The two Typst protocol functions are therefore declared with `Int` (i32) pointer parameters:

```moonbit
fn send_result_to_host_raw(ptr : Int, len : Int) = "typst_env" "wasm_minimal_protocol_send_result_to_host"
fn write_args_to_buffer_raw(ptr : Int) = "typst_env" "wasm_minimal_protocol_write_args_to_buffer"
```

### Getting the data pointer

In MoonBit's wasm linear-memory backend, a `FixedArray[Byte]` value is a heap pointer with the following layout:

```
heap_ptr + 0 ..  3 : refcount (i32)
heap_ptr + 4 ..  7 : packed length + type info (i32)
heap_ptr + 8 .. +N : actual byte data
```

The data pointer (what the host expects) is therefore `heap_ptr + 8`. An `extern "wasm"` helper computes this offset:

```moonbit
#borrow(arr)
extern "wasm" fn fixedarray_data_ptr(arr : FixedArray[Byte]) -> Int =
  #|(func (param i32) (result i32)
  #|  local.get 0
  #|  i32.const 8
  #|  i32.add)
```

### Preventing early decref

MoonBit's optimizer may schedule the reference count decrement for a value immediately after its last visible use. Without precaution, MoonBit would decref (and potentially free) the array buffer *before* calling the host function, resulting in a use-after-free.

A dummy `let _ = arr.length()` call placed *after* the host call prevents this: it gives the compiler a later visible use of `arr`, so the decref is guaranteed to happen only after the host has finished reading or writing the buffer.

```moonbit
fn send_result_to_host(arr : FixedArray[Byte]) -> Unit {
  let ptr = fixedarray_data_ptr(arr)
  let len = arr.length()
  send_result_to_host_raw(ptr, len)
  let _ = arr.length() // keep arr alive until after the host read
}
```

### Avoiding unexpected imports

MoonBit's `wasm` target imports `spectest.print_char` when printing (e.g., via `println` or `panic`). Because Typst does not provide this function, the example deliberately avoids any printing. For `will_panic`, an inline `unreachable` WAT instruction is used instead:

```moonbit
extern "wasm" fn wasm_trap() -> Int =
  #|(func (result i32) unreachable)
```


