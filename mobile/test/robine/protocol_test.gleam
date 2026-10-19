import gleam/bit_array
import robine/protocol.{Done, Page}

pub fn crc32_reference_vector_test() {
  assert protocol.crc32(<<"123456789":utf8>>) == 0xCBF43926
}

pub fn parses_a_response_page_test() {
  let payload = <<"{\"status\":\"ok\"}":utf8>>
  let checksum = protocol.crc32(payload)
  let size = bit_array.byte_size(payload)
  let bytes = <<
    0x52, 0x57, 1, 1, 42:size(32), 0:size(16), 1:size(16), size:size(32),
    checksum:size(32), payload:bits,
  >>
  let assert Ok(page) = protocol.parse_page(bytes)
  assert page
    == Page(
      final: True,
      sequence: 42,
      index: 0,
      count: 1,
      total: size,
      crc: checksum,
      payload:,
    )
  assert protocol.add_page(Error(Nil), page) == Ok(Done("{\"status\":\"ok\"}"))
}

pub fn rejects_a_corrupted_response_test() {
  let payload = <<"{}":utf8>>
  let bytes = <<
    0x52, 0x57, 1, 1, 1:size(32), 0:size(16), 1:size(16), 2:size(32), 0:size(32),
    payload:bits,
  >>
  let assert Ok(page) = protocol.parse_page(bytes)
  assert protocol.add_page(Error(Nil), page)
    == Error("Réponse Bluetooth incomplète ou corrompue")
  assert protocol.parse_page(<<0x52, 0x57>>)
    == Error("En-tête de réponse Bluetooth incomplet")
}

pub fn splits_commands_in_chunks_test() {
  let json = bit_array.from_string(repeat("a", 399))
  let assert Ok(text) = bit_array.to_string(json)
  let chunks = protocol.command_chunks(text)
  assert chunks
    |> map_sizes
    == [180, 180, 40]
}

fn map_sizes(chunks: List(BitArray)) -> List(Int) {
  case chunks {
    [] -> []
    [first, ..rest] -> [bit_array.byte_size(first), ..map_sizes(rest)]
  }
}

fn repeat(value: String, times: Int) -> String {
  case times {
    0 -> ""
    _ -> value <> repeat(value, times - 1)
  }
}
