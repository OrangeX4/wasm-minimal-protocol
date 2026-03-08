// ===
// Functions for the protocol
//
// In MoonBit's wasm (linear-memory) backend, only primitive types (Int, UInt,
// etc.) are valid for the `fn = "module" "func"` stub import syntax. Complex
// types such as FixedArray[Byte] are not accepted and will produce a
// compile-time "Invalid stub type" error.
//
// Instead, we declare the host imports with Int (i32) for pointer parameters,
// and use an `extern "wasm"` helper to extract the raw data pointer.
//
// Memory layout of FixedArray[Byte] in wasm linear memory:
//   heap_ptr + 0 ..  3 : refcount (i32)
//   heap_ptr + 4 ..  7 : packed length + type info (i32)
//   heap_ptr + 8 .. +N : actual byte data
// → data pointer = heap_ptr + 8

fn send_result_to_host_raw(ptr : Int, len : Int) = "typst_env" "wasm_minimal_protocol_send_result_to_host"

fn write_args_to_buffer_raw(ptr : Int) = "typst_env" "wasm_minimal_protocol_write_args_to_buffer"

// Returns a pointer to the first data byte of `arr` (heap_ptr + 8).
#borrow(arr)
extern "wasm" fn fixedarray_data_ptr(arr : FixedArray[Byte]) -> Int =
  #|(func (param i32) (result i32)
  #|  local.get 0
  #|  i32.const 8
  #|  i32.add)

// Trap unconditionally — used for will_panic.
// Uses inline WAT `unreachable` to avoid importing spectest.print_char
// (which Typst does not provide).
extern "wasm" fn wasm_trap() -> Int =
  #|(func (result i32) unreachable)

// Send the byte contents of `arr` to the Typst host as the function result.
//
// Important: the dummy `arr.length()` at the end prevents MoonBit from
// performing an early decref on `arr` before the host has finished reading
// from it. Without this call, the compiler would free `arr` immediately after
// deriving the data pointer, causing a use-after-free inside the host.
fn send_result_to_host(arr : FixedArray[Byte]) -> Unit {
  let ptr = fixedarray_data_ptr(arr)
  let len = arr.length()
  send_result_to_host_raw(ptr, len)
  let _ = arr.length() // keep arr alive until after the host read
}

// Ask the Typst host to write the current argument bytes into `arr`.
//
// Same rationale as send_result_to_host: the dummy arr.length() prevents
// an early decref before the host has finished writing.
fn write_args_to_buffer(arr : FixedArray[Byte]) -> Unit {
  write_args_to_buffer_raw(fixedarray_data_ptr(arr))
  let _ = arr.length() // keep arr alive until after the host write
}

// ===

pub fn hello() -> Int {
  let msg : FixedArray[Byte] = [
    b'H', b'e', b'l', b'l', b'o', b' ', b'f', b'r', b'o', b'm', b' ', b'w', b'a',
    b's', b'm', b'!', b'!', b'!',
  ]
  send_result_to_host(msg)
  0
}

pub fn double_it(arg1_len : Int) -> Int {
  let result : FixedArray[Byte] = FixedArray::make(arg1_len * 2, b'\x00')
  write_args_to_buffer(result)
  for i in 0..<arg1_len {
    result[arg1_len + i] = result[i]
  }
  send_result_to_host(result)
  0
}

pub fn concatenate(arg1_len : Int, arg2_len : Int) -> Int {
  let args : FixedArray[Byte] = FixedArray::make(arg1_len + arg2_len, b'\x00')
  write_args_to_buffer(args)
  let result : FixedArray[Byte] = FixedArray::make(arg1_len + 1 + arg2_len, b'\x00')
  for i in 0..<arg1_len {
    result[i] = args[i]
  }
  result[arg1_len] = b'*'
  for i in 0..<arg2_len {
    result[arg1_len + 1 + i] = args[arg1_len + i]
  }
  send_result_to_host(result)
  0
}

pub fn shuffle(arg1_len : Int, arg2_len : Int, arg3_len : Int) -> Int {
  let total_len = arg1_len + arg2_len + arg3_len
  let args : FixedArray[Byte] = FixedArray::make(total_len, b'\x00')
  write_args_to_buffer(args)
  // Result layout: arg3 '-' arg1 '-' arg2
  let result : FixedArray[Byte] = FixedArray::make(total_len + 2, b'\x00')
  let mut pos = 0
  for i in 0..<arg3_len {
    result[pos] = args[arg1_len + arg2_len + i]
    pos += 1
  }
  result[pos] = b'-'
  pos += 1
  for i in 0..<arg1_len {
    result[pos] = args[i]
    pos += 1
  }
  result[pos] = b'-'
  pos += 1
  for i in 0..<arg2_len {
    result[pos] = args[arg1_len + i]
    pos += 1
  }
  send_result_to_host(result)
  0
}

pub fn returns_ok() -> Int {
  let msg : FixedArray[Byte] = [
    b'T', b'h', b'i', b's', b' ', b'i', b's', b' ', b'a', b'n', b' ', b'`', b'O',
    b'k', b'`',
  ]
  send_result_to_host(msg)
  0
}

pub fn returns_err() -> Int {
  let msg : FixedArray[Byte] = [
    b'T', b'h', b'i', b's', b' ', b'i', b's', b' ', b'a', b'n', b' ', b'`', b'E',
    b'r', b'r', b'`',
  ]
  send_result_to_host(msg)
  1
}

pub fn will_panic() -> Int {
  wasm_trap()
}


