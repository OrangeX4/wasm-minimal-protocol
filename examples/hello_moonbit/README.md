# MoonBit WASM plugin example

This is a bare-bones Typst plugin, written in [MoonBit](https://www.moonbitlang.com/).

## Compile

To compile this example, you need to [install MoonBit CLI Tools](https://www.moonbitlang.com/download/#moonbit-cli-tools). Then, build the project for the `wasm` (linear-memory) target:

```sh
moon build --target wasm --release
cp _build/wasm/release/build/hello.wasm .
```

## Build with Typst

Simply run `typst compile hello.typ`, and observe that it works!
