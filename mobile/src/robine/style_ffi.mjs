export function offset(width, height) {
  return { width, height };
}

export function scale(value) {
  return ["transform", [{ scale: value }]];
}

export function translate_x(value) {
  return ["transform", [{ translateX: value }]];
}

export function tabular_nums() {
  return ["fontVariant", ["tabular-nums"]];
}
