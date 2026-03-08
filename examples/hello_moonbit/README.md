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
cp target/wasm/release/build/hello.wasm .
```

The output file is placed by moon at `target/wasm/release/build/hello.wasm` (the name `hello` comes from the `"name"` field in `moon.mod.json`).

## Build with Typst

Simply run `typst compile hello.typ`, and observe that it works!

## Notes on the implementation

### Protocol FFI

MoonBit's `wasm` target uses linear memory. In this backend, `FixedArray[Byte]` values are passed to foreign functions as an `i32` pointing directly to the byte data—matching the `uint8_t*` convention in MoonBit's C backend. This lets the plugin pass buffer addresses to the two Typst protocol functions:

- `wasm_minimal_protocol_send_result_to_host(ptr, len)` — send result bytes to Typst
- `wasm_minimal_protocol_write_args_to_buffer(ptr)` — receive argument bytes from Typst

Both are imported using MoonBit's `fn = "module" "func"` import syntax:

```moonbit
#borrow(ptr)
fn send_result_to_host(ptr : FixedArray[Byte], len : Int) = "typst_env" "wasm_minimal_protocol_send_result_to_host"
```

The `#borrow` attribute tells MoonBit that the host function does not take ownership of the buffer, so MoonBit manages the reference count itself without requiring the host to call `$moonbit.decref`.

### Avoiding unexpected imports

MoonBit's `wasm` target imports `spectest.print_char` when printing (e.g., via `println` or `panic`). Because Typst does not provide this function, the example deliberately avoids any printing. For `will_panic`, an inline `unreachable` WAT instruction is used instead:

```moonbit
extern "wasm" fn wasm_trap() -> Int =
  #|(func (result i32) unreachable)
```

