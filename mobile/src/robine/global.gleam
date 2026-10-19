//// Module-level mutable values, the Gleam side of what the TypeScript app
//// kept in `let` variables at the top of a module.

pub type Ref(a)

/// The value registered under `name`, created by `initial` on first use.
@external(javascript, "./global_ffi.mjs", "named")
pub fn named(name: String, initial: fn() -> a) -> Ref(a)

@external(javascript, "./global_ffi.mjs", "get")
pub fn get(ref: Ref(a)) -> a

@external(javascript, "./global_ffi.mjs", "set")
pub fn set(ref: Ref(a), value: a) -> Nil

pub fn update(ref: Ref(a), change: fn(a) -> a) -> Nil {
  set(ref, change(get(ref)))
}
