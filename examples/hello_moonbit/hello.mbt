// ===
// Functions for the protocol
//
// In MoonBit's wasm backend, FixedArray[Byte] is passed to foreign functions
// as an i32 pointing directly to the byte data (the same convention as
// uint8_t* in the C backend). The `#borrow` attribute tells MoonBit that
// the callee does not take ownership, so MoonBit manages reference counting
// itself without requiring the host to call $moonbit.decref.

#borrow(ptr)
fn send_result_to_host(ptr : FixedArray[Byte], len : Int) = "typst_env" "wasm_minimal_protocol_send_result_to_host"

#borrow(buf)
fn write_args_to_buffer(buf : FixedArray[Byte]) = "typst_env" "wasm_minimal_protocol_write_args_to_buffer"

// Trap unconditionally — used for will_panic.
// This inline WAT function executes `unreachable`, which traps the runtime
// without any imports.
extern "wasm" fn wasm_trap() -> Int =
  #|(func (result i32) unreachable)

// ===

pub fn hello() -> Int {
  let msg : FixedArray[Byte] = [
    b'H', b'e', b'l', b'l', b'o', b' ', b'f', b'r', b'o', b'm', b' ', b'w', b'a',
    b's', b'm', b'!', b'!', b'!',
  ]
  send_result_to_host(msg, msg.length())
  0
}

pub fn double_it(arg1_len : Int) -> Int {
  let result : FixedArray[Byte] = FixedArray::make(arg1_len * 2, b'\x00')
  write_args_to_buffer(result)
  for i in 0..<arg1_len {
    result[arg1_len + i] = result[i]
  }
  send_result_to_host(result, result.length())
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
  send_result_to_host(result, result.length())
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
  send_result_to_host(result, result.length())
  0
}

pub fn returns_ok() -> Int {
  let msg : FixedArray[Byte] = [
    b'T', b'h', b'i', b's', b' ', b'i', b's', b' ', b'a', b'n', b' ', b'`', b'O',
    b'k', b'`',
  ]
  send_result_to_host(msg, msg.length())
  0
}

pub fn returns_err() -> Int {
  let msg : FixedArray[Byte] = [
    b'T', b'h', b'i', b's', b' ', b'i', b's', b' ', b'a', b'n', b' ', b'`', b'E',
    b'r', b'r', b'`',
  ]
  send_result_to_host(msg, msg.length())
  1
}

pub fn will_panic() -> Int {
  wasm_trap()
}

