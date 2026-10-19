//// Helpers for the clock's JSON, where absent and `null` fields mean the same.

import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/option.{type Option, None}

/// A field that may be absent or `null`.
pub fn optional(
  key: String,
  decoder: Decoder(a),
  next: fn(Option(a)) -> Decoder(b),
) -> Decoder(b) {
  decode.optional_field(key, None, decode.optional(decoder), next)
}

/// A field that may be absent or `null`, replaced by `default`.
pub fn defaulted(
  key: String,
  default: a,
  decoder: Decoder(a),
  next: fn(a) -> Decoder(b),
) -> Decoder(b) {
  use value <- optional(key, decoder)
  next(option.unwrap(value, default))
}

/// Integers, also when the clock sends them as floats.
pub fn number() -> Decoder(Int) {
  decode.one_of(decode.int, [decode.float |> decode.map(float.round)])
}

/// Continues with the value when the check passed, or fails the decoding,
/// expecting `name`; `zero` only keeps the decoder going to collect errors.
pub fn require(
  checked: Result(a, e),
  name: String,
  zero: a,
  next: fn(a) -> Decoder(b),
) -> Decoder(b) {
  case checked {
    Ok(value) -> next(value)
    Error(_) -> decode.failure(zero, name) |> decode.then(next)
  }
}
