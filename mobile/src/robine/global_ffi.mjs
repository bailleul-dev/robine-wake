const refs = new Map();

export function named(name, initial) {
  if (!refs.has(name)) refs.set(name, { value: initial() });
  return refs.get(name);
}

export function get(ref) {
  return ref.value;
}

export function set(ref, value) {
  ref.value = value;
  return undefined;
}
