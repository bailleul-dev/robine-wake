//// Framing of the Bluetooth transport: commands are written in chunks,
//// responses are read back as checksummed pages.

import gleam/bit_array
import gleam/int
import gleam/list

pub const service_uuid = "8AD00001-A7A9-4EF7-A259-67C9C65E4C10"

pub const command_uuid = "8AD00002-A7A9-4EF7-A259-67C9C65E4C10"

pub const response_uuid = "8AD00003-A7A9-4EF7-A259-67C9C65E4C10"

/// Largest response accepted, in bytes.
pub const maximum_response = 1_048_576

const chunk_size = 180

pub fn crc32(bytes: BitArray) -> Int {
  int.bitwise_exclusive_or(crc32_loop(bytes, 0xFFFFFFFF), 0xFFFFFFFF)
}

fn crc32_loop(bytes: BitArray, crc: Int) -> Int {
  case bytes {
    <<byte, rest:bytes>> ->
      crc32_loop(rest, crc32_byte(int.bitwise_exclusive_or(crc, byte), 8))
    _ -> crc
  }
}

fn crc32_byte(value: Int, bits: Int) -> Int {
  case bits {
    0 -> value
    _ -> {
      let shifted = int.bitwise_shift_right(value, 1)
      let next = case int.bitwise_and(value, 1) {
        1 -> int.bitwise_exclusive_or(shifted, 0xEDB88320)
        _ -> shifted
      }
      crc32_byte(next, bits - 1)
    }
  }
}

/// A command line split into writes of at most 180 bytes.
pub fn command_chunks(json: String) -> List(BitArray) {
  split(bit_array.from_string(json <> "\n"), [])
}

fn split(bytes: BitArray, chunks: List(BitArray)) -> List(BitArray) {
  case bit_array.slice(bytes, 0, chunk_size) {
    Ok(chunk) ->
      split(
        bit_array.slice(
          bytes,
          chunk_size,
          bit_array.byte_size(bytes) - chunk_size,
        )
          |> unwrap_bits,
        [chunk, ..chunks],
      )
    Error(Nil) ->
      case bit_array.byte_size(bytes) {
        0 -> list.reverse(chunks)
        _ -> list.reverse([bytes, ..chunks])
      }
  }
}

fn unwrap_bits(result: Result(BitArray, Nil)) -> BitArray {
  case result {
    Ok(bits) -> bits
    Error(Nil) -> <<>>
  }
}

pub type Page {
  Page(
    final: Bool,
    sequence: Int,
    index: Int,
    count: Int,
    total: Int,
    crc: Int,
    payload: BitArray,
  )
}

pub fn parse_page(bytes: BitArray) -> Result(Page, String) {
  case bytes {
    <<
      0x52,
      0x57,
      1,
      flags,
      sequence:size(32),
      index:size(16),
      count:size(16),
      total:size(32),
      crc:size(32),
      payload:bytes,
    >> ->
      Ok(Page(
        final: int.bitwise_and(flags, 1) == 1,
        sequence:,
        index:,
        count:,
        total:,
        crc:,
        payload:,
      ))
    <<_:bytes-size(20), _:bytes>> ->
      Error("En-tête de réponse Bluetooth invalide")
    _ -> Error("En-tête de réponse Bluetooth incomplet")
  }
}

/// Pages read so far for one response.
pub opaque type Assembly {
  Assembly(first: Page, pages: Int, payload: BitArray)
}

pub type Step {
  /// Read the next page.
  Continue(Assembly)
  /// The response is complete.
  Done(String)
}

/// Adds a page to the response being read, `None` for the first one.
pub fn add_page(
  assembly: Result(Assembly, Nil),
  page: Page,
) -> Result(Step, String) {
  let #(first, expected_index, payload) = case assembly {
    Ok(Assembly(first:, pages:, payload:)) -> #(first, pages, payload)
    Error(Nil) -> #(page, 0, <<>>)
  }
  let consistent =
    page.index == expected_index
    && page.sequence == first.sequence
    && page.count == first.count
    && page.total == first.total
    && page.crc == first.crc
    && page.count != 0
    && page.total <= maximum_response
  case consistent {
    False -> Error("Pages Bluetooth incohérentes")
    True -> {
      let payload = bit_array.append(payload, page.payload)
      case page.final {
        False ->
          Ok(Continue(Assembly(first:, pages: expected_index + 1, payload:)))
        True -> {
          let complete =
            expected_index + 1 == page.count
            && bit_array.byte_size(payload) == page.total
            && crc32(payload) == page.crc
          case complete, bit_array.to_string(payload) {
            True, Ok(text) -> Ok(Done(text))
            _, _ -> Error("Réponse Bluetooth incomplète ou corrompue")
          }
        }
      }
    }
  }
}
