export function style_object(entries) {
  const result = {};
  for (const [key, value] of entries.toArray()) result[key] = value;
  return result;
}
