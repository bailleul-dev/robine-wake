//// The sounds the clock can play.

import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import robine/decoding.{defaulted, optional}
import robine/id.{type Id}

pub type Sound {
  Sound(
    id: Id(Sound),
    title: String,
    artist: Option(String),
    intensity: Intensity,
  )
}

pub type Intensity {
  Gentle
  Bright
  Strong
  Meditation
  Custom
  Unrated
  OtherIntensity(String)
}

/// What the clock plays for an alarm that names no sound.
pub fn built_in() -> Id(Sound) {
  id.from_string("default")
}

pub fn is_strong(sound: Sound) -> Bool {
  sound.intensity == Strong
}

pub fn intensity_label(intensity: Intensity) -> String {
  case intensity {
    Gentle -> "Doux"
    Bright -> "Lumineux"
    Strong -> "Fort"
    Meditation -> "Méditation"
    Custom -> "Personnel"
    Unrated -> ""
    OtherIntensity(other) -> string.capitalise(other)
  }
}

/// The first sound of this intensity, the first sound at all, or the clock's.
pub fn default_sound(sounds: List(Sound), intensity: Intensity) -> Id(Sound) {
  case list.find(sounds, fn(sound) { sound.intensity == intensity }), sounds {
    Ok(sound), _ -> sound.id
    Error(Nil), [first, ..] -> first.id
    Error(Nil), [] -> built_in()
  }
}

pub fn decoder() -> Decoder(Sound) {
  use sound_id <- decode.field("id", decode.string)
  use title <- defaulted("title", sound_id, decode.string)
  use artist <- optional("artist", decode.string)
  use intensity <- optional("intensity", decode.string)
  let artist =
    option.then(artist, fn(artist) {
      case string.trim(artist) {
        "" -> None
        _ -> Some(artist)
      }
    })
  let intensity = case intensity {
    None | Some("") -> Unrated
    Some("gentle") -> Gentle
    Some("bright") -> Bright
    Some("strong") -> Strong
    Some("meditation") -> Meditation
    Some("custom") -> Custom
    Some(other) -> OtherIntensity(other)
  }
  decode.success(Sound(
    id: id.from_string(sound_id),
    title:,
    artist:,
    intensity:,
  ))
}
