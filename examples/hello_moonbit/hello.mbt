// Protocol host imports — only primitive types are valid for wasm stub FFI.
fn send_result_to_host_raw(ptr : Int, len : Int) = "typst_env" "wasm_minimal_protocol_send_result_to_host"
fn write_args_to_buffer_raw(ptr : Int) = "typst_env" "wasm_minimal_protocol_write_args_to_buffer"

// Returns a raw pointer to the first data byte of bs (heap_ptr + 8).
// FixedArray[Byte] and Bytes share the same linear-memory layout, so this
// helper works for both via the zero-cost `to_bytes` cast below.
#borrow(bs)
extern "wasm" fn data_ptr(bs : Bytes) -> Int =
  #|(func (param i32) (result i32)
  #|  local.get 0
  #|  i32.const 8
  #|  i32.add)

// Inline trap — avoids importing spectest.print_char which Typst doesn't provide.
extern "wasm" fn wasm_trap() -> Int =
  #|(func (result i32) unreachable)

// FixedArray[Byte] and Bytes have the same representation; this cast is free.
fn to_bytes(arr : FixedArray[Byte]) -> Bytes = "%identity"

fn send_result(bs : Bytes) -> Unit {
  send_result_to_host_raw(data_ptr(bs), bs.length())
}

fn write_args(arr : FixedArray[Byte]) -> Unit {
  let bs = to_bytes(arr)
  write_args_to_buffer_raw(data_ptr(bs))
}

// ===

pub fn hello() -> Int {
  send_result(b"Hello from wasm!!!")
  0
}

pub fn double_it(arg1_len : Int) -> Int {
  let result = FixedArray::make(arg1_len * 2, b'\x00')
  write_args(result)
  for i in 0..<arg1_len {
    result[arg1_len + i] = result[i]
  }
  send_result(to_bytes(result))
  0
}

pub fn concatenate(arg1_len : Int, arg2_len : Int) -> Int {
  let args = FixedArray::make(arg1_len + arg2_len, b'\x00')
  write_args(args)
  let result = FixedArray::make(arg1_len + 1 + arg2_len, b'\x00')
  for i in 0..<arg1_len {
    result[i] = args[i]
  }
  result[arg1_len] = b'*'
  for i in 0..<arg2_len {
    result[arg1_len + 1 + i] = args[arg1_len + i]
  }
  send_result(to_bytes(result))
  0
}

pub fn shuffle(arg1_len : Int, arg2_len : Int, arg3_len : Int) -> Int {
  let total_len = arg1_len + arg2_len + arg3_len
  let args = FixedArray::make(total_len, b'\x00')
  write_args(args)
  // Result layout: arg3 '-' arg1 '-' arg2
  let result = FixedArray::make(total_len + 2, b'\x00')
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
  send_result(to_bytes(result))
  0
}

pub fn returns_ok() -> Int {
  send_result(b"This is an `Ok`")
  0
}

pub fn returns_err() -> Int {
  send_result(b"This is an `Err`")
  1
}

pub fn will_panic() -> Int {
  wasm_trap()
}

// ===== CBOR support for complex_data =====

// Inline WASM: assemble f64 from hi (bits 63-32) and lo (bits 31-0) as unsigned 32-bit halves.
extern "wasm" fn f64_from_parts(hi : Int, lo : Int) -> Double =
  #|(func (param i32 i32) (result f64)
  #|  local.get 0
  #|  i64.extend_i32_u
  #|  i64.const 32
  #|  i64.shl
  #|  local.get 1
  #|  i64.extend_i32_u
  #|  i64.or
  #|  f64.reinterpret_i64)

// Inline WASM: extract high 32 bits (bits 63-32) from f64 IEEE 754 representation.
extern "wasm" fn f64_hi(v : Double) -> Int =
  #|(func (param f64) (result i32)
  #|  local.get 0
  #|  i64.reinterpret_f64
  #|  i64.const 32
  #|  i64.shr_u
  #|  i32.wrap_i64)

// Inline WASM: extract low 32 bits (bits 31-0) from f64 IEEE 754 representation.
extern "wasm" fn f64_lo(v : Double) -> Int =
  #|(func (param f64) (result i32)
  #|  local.get 0
  #|  i64.reinterpret_f64
  #|  i32.wrap_i64)

// Inline WASM: (n >>> shift) & 0xFF — logical right shift to extract one byte.
extern "wasm" fn shr_byte(n : Int, shift : Int) -> Int =
  #|(func (param i32 i32) (result i32)
  #|  local.get 0
  #|  local.get 1
  #|  i32.shr_u
  #|  i32.const 255
  #|  i32.and)

// Read 4 bytes at buf[pos..pos+4] as a big-endian Int.
// The multipliers are 2^24, 2^16, 2^8, 2^0 for each byte position.
// Integer overflow is intentional and preserves the correct bit pattern on 32-bit WASM.
fn read_be4(buf : FixedArray[Byte], pos : Int) -> Int {
  buf[pos].to_int() * 16777216 +
  buf[pos + 1].to_int() * 65536 +
  buf[pos + 2].to_int() * 256 +
  buf[pos + 3].to_int()
}

// Write n as 4 big-endian bytes into buf starting at pos.
fn write_be4(buf : FixedArray[Byte], pos : Int, n : Int) -> Unit {
  buf[pos] = shr_byte(n, 24).to_byte()
  buf[pos + 1] = shr_byte(n, 16).to_byte()
  buf[pos + 2] = shr_byte(n, 8).to_byte()
  buf[pos + 3] = shr_byte(n, 0).to_byte()
}

// Decode a CBOR unsigned integer from buf[pos..]. Returns (value, new_pos).
fn cbor_uint(buf : FixedArray[Byte], pos : Int, add : Int) -> (Int, Int) {
  if add < 24 {
    (add, pos)
  } else if add == 24 {
    (buf[pos].to_int(), pos + 1)
  } else if add == 25 {
    (buf[pos].to_int() * 256 + buf[pos + 1].to_int(), pos + 2)
  } else if add == 26 {
    (read_be4(buf, pos), pos + 4)
  } else {
    // add == 27: 64-bit uint — skip 8 bytes, return 0 (not needed for small values)
    (0, pos + 8)
  }
}

// Decode a CBOR number (integer or float64) from buf[pos..]. Returns (Double value, new_pos).
fn cbor_number(buf : FixedArray[Byte], pos : Int) -> (Double, Int) {
  let b = buf[pos].to_int()
  let major = b / 32
  let add = b % 32
  let pos1 = pos + 1
  match major {
    0 => {
      let (v, p) = cbor_uint(buf, pos1, add)
      (v.to_double(), p)
    }
    1 => {
      let (n, p) = cbor_uint(buf, pos1, add)
      ((-1 - n).to_double(), p)
    }
    7 => {
      if add == 27 {
        (f64_from_parts(read_be4(buf, pos1), read_be4(buf, pos1 + 4)), pos1 + 8)
      } else {
        // float16 / float32 / other — not needed for this use case
        (0.0, pos1)
      }
    }
    _ => (0.0, pos)
  }
}

pub fn complex_data(data_len : Int) -> Int {
  let buf = FixedArray::make(data_len, b'\x00')
  write_args(buf)
  // Parse CBOR map: { x: int, y: float64 }
  let map_add = buf[0].to_int() % 32
  let (count, pos0) = cbor_uint(buf, 1, map_add)
  let mut pos = pos0
  let mut x_val = 0.0
  let mut y_val = 0.0
  for _ in 0..<count {
    // Read text-string key
    let k_add = buf[pos].to_int() % 32
    let (klen, kp) = cbor_uint(buf, pos + 1, k_add)
    let is_x = klen == 1 && buf[kp] == b'x'
    let is_y = klen == 1 && buf[kp] == b'y'
    pos = kp + klen
    // Read value
    let (val, np) = cbor_number(buf, pos)
    pos = np
    if is_x {
      x_val = val
    } else if is_y {
      y_val = val
    }
  }
  // Encode result as CBOR float64: 0xfb followed by 8 big-endian bytes
  let sum = x_val + y_val
  let out = FixedArray::make(9, b'\x00')
  out[0] = b'\xfb'
  write_be4(out, 1, f64_hi(sum))
  write_be4(out, 5, f64_lo(sum))
  send_result(to_bytes(out))
  0
}
