//// Identifiers the clock gives its things. The type parameter names the kind
//// of thing, so a sound's id cannot stand for an alarm's.

import gleam/dynamic/decode.{type Decoder}
import gleam/list

pub opaque type Id(of) {
  Id(String)
}

pub fn from_string(text: String) -> Id(of) {
  Id(text)
}

pub fn to_string(id: Id(of)) -> String {
  let Id(text) = id
  text
}

pub fn decoder() -> Decoder(Id(of)) {
  decode.map(decode.string, Id)
}

/// The item a picker reports by the text of its id.
pub fn find(
  items: List(a),
  text: String,
  id_of: fn(a) -> Id(of),
) -> Result(a, Nil) {
  list.find(items, fn(item) { to_string(id_of(item)) == text })
}
