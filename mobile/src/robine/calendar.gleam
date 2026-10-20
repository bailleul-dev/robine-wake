//// Days of the week and times of day, as the clock schedules alarms.

import gleam/int
import gleam/list
import gleam/order.{type Order}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/time/timestamp.{type Timestamp}

pub type Weekday {
  Monday
  Tuesday
  Wednesday
  Thursday
  Friday
  Saturday
  Sunday
}

pub const week = [
  Monday,
  Tuesday,
  Wednesday,
  Thursday,
  Friday,
  Saturday,
  Sunday,
]

/// ISO 8601 number of the day, Monday being 1.
pub fn number(day: Weekday) -> Int {
  case day {
    Monday -> 1
    Tuesday -> 2
    Wednesday -> 3
    Thursday -> 4
    Friday -> 5
    Saturday -> 6
    Sunday -> 7
  }
}

pub fn from_number(number: Int) -> Result(Weekday, Nil) {
  case number {
    1 -> Ok(Monday)
    2 -> Ok(Tuesday)
    3 -> Ok(Wednesday)
    4 -> Ok(Thursday)
    5 -> Ok(Friday)
    6 -> Ok(Saturday)
    7 -> Ok(Sunday)
    _ -> Error(Nil)
  }
}

pub fn name(day: Weekday) -> String {
  case day {
    Monday -> "Lundi"
    Tuesday -> "Mardi"
    Wednesday -> "Mercredi"
    Thursday -> "Jeudi"
    Friday -> "Vendredi"
    Saturday -> "Samedi"
    Sunday -> "Dimanche"
  }
}

pub fn initial(day: Weekday) -> String {
  string.slice(name(day), 0, 1)
}

/// At least one day of the week.
pub opaque type Days {
  Days(Set(Weekday))
}

pub fn days(of days: List(Weekday)) -> Result(Days, Nil) {
  case days {
    [] -> Error(Nil)
    _ -> Ok(Days(set.from_list(days)))
  }
}

pub const weekdays = [Monday, Tuesday, Wednesday, Thursday, Friday]

pub fn every_day() -> Days {
  Days(set.from_list(week))
}

/// The days in the order of the week.
pub fn day_list(days: Days) -> List(Weekday) {
  let Days(days) = days
  list.filter(week, set.contains(days, _))
}

pub fn days_label(days: Days) -> String {
  let Days(chosen) = days
  let same = fn(expected) { chosen == set.from_list(expected) }
  case same(weekdays), same([Saturday, Sunday]), same(week) {
    True, _, _ -> "En semaine"
    _, True, _ -> "Le week-end"
    _, _, True -> "Tous les jours"
    _, _, _ -> day_list(days) |> list.map(initial) |> string.join(" · ")
  }
}

/// A time of day to the minute.
pub opaque type Time {
  Time(hour: Int, minute: Int)
}

pub fn time(hour: Int, minute: Int) -> Result(Time, Nil) {
  case hour >= 0 && hour < 24 && minute >= 0 && minute < 60 {
    True -> Ok(Time(hour:, minute:))
    False -> Error(Nil)
  }
}

pub fn hour(time: Time) -> Int {
  time.hour
}

pub fn minute(time: Time) -> Int {
  time.minute
}

/// `HH:MM`, ignoring seconds when there are some.
pub fn parse_time(text: String) -> Result(Time, Nil) {
  case string.split(text, ":") {
    [hour, minute, ..] -> {
      use hour <- result.try(int.parse(hour))
      use minute <- result.try(int.parse(minute))
      time(hour, minute)
    }
    _ -> Error(Nil)
  }
}

/// `07:05`.
pub fn time_to_string(time: Time) -> String {
  two_digits(time.hour) <> ":" <> two_digits(time.minute)
}

pub fn compare_times(left: Time, right: Time) -> Order {
  int.compare(left.hour * 60 + left.minute, right.hour * 60 + right.minute)
}

pub fn two_digits(value: Int) -> String {
  string.pad_start(int.to_string(value), 2, "0")
}

/// An RFC 3339 date, as the clock writes them.
pub fn parse_instant(text: String) -> Result(Timestamp, Nil) {
  timestamp.parse_rfc3339(text)
}
