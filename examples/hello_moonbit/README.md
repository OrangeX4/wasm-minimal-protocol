# MoonBit wasm plugin example

This is a bare-bones Typst plugin, written in [MoonBit](https://www.moonbitlang.com/).

## Compile

To compile this example, you need the [MoonBit toolchain](https://www.moonbitlang.com/download/). Install it in Linux & macOS with:

```sh
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

Windows users can install it with:

```sh
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser; irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

After installing, `moon` should be available on your PATH. Then, build the project for the `wasm` (linear-memory) target:

```sh
moon build --target wasm --release
cp _build/wasm/release/build/hello.wasm .
```

## Build with Typst

Simply run `typst compile hello.typ`.
