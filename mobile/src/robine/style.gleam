//// Style properties of React Native, typed by what they take. Sizes are in
//// points; `pct` variants take a percentage such as "18%".

pub type Style

@external(javascript, "./native_ffi.mjs", "prop")
pub fn raw(key: String, value: a) -> Style

pub fn color(value: String) -> Style {
  raw("color", value)
}

pub fn background_color(value: String) -> Style {
  raw("backgroundColor", value)
}

pub fn border_color(value: String) -> Style {
  raw("borderColor", value)
}

pub fn border_top_color(value: String) -> Style {
  raw("borderTopColor", value)
}

pub fn border_right_color(value: String) -> Style {
  raw("borderRightColor", value)
}

pub fn shadow_color(value: String) -> Style {
  raw("shadowColor", value)
}

pub fn font_weight(value: String) -> Style {
  raw("fontWeight", value)
}

pub fn align_items(value: String) -> Style {
  raw("alignItems", value)
}

pub fn align_self(value: String) -> Style {
  raw("alignSelf", value)
}

pub fn flex_direction(value: String) -> Style {
  raw("flexDirection", value)
}

pub fn justify_content(value: String) -> Style {
  raw("justifyContent", value)
}

pub fn flex_wrap(value: String) -> Style {
  raw("flexWrap", value)
}

pub fn text_align(value: String) -> Style {
  raw("textAlign", value)
}

pub fn position(value: String) -> Style {
  raw("position", value)
}

pub fn overflow(value: String) -> Style {
  raw("overflow", value)
}

pub fn cursor(value: String) -> Style {
  raw("cursor", value)
}

pub fn outline_style(value: String) -> Style {
  raw("outlineStyle", value)
}

pub fn text_transform(value: String) -> Style {
  raw("textTransform", value)
}

pub fn font_size(value: Int) -> Style {
  raw("fontSize", value)
}

pub fn border_radius(value: Int) -> Style {
  raw("borderRadius", value)
}

pub fn gap(value: Int) -> Style {
  raw("gap", value)
}

pub fn height(value: Int) -> Style {
  raw("height", value)
}

pub fn border_width(value: Int) -> Style {
  raw("borderWidth", value)
}

pub fn border_top_width(value: Int) -> Style {
  raw("borderTopWidth", value)
}

pub fn border_right_width(value: Int) -> Style {
  raw("borderRightWidth", value)
}

pub fn padding(value: Int) -> Style {
  raw("padding", value)
}

pub fn padding_horizontal(value: Int) -> Style {
  raw("paddingHorizontal", value)
}

pub fn padding_vertical(value: Int) -> Style {
  raw("paddingVertical", value)
}

pub fn padding_top(value: Int) -> Style {
  raw("paddingTop", value)
}

pub fn padding_bottom(value: Int) -> Style {
  raw("paddingBottom", value)
}

pub fn margin_top(value: Int) -> Style {
  raw("marginTop", value)
}

pub fn margin_bottom(value: Int) -> Style {
  raw("marginBottom", value)
}

pub fn line_height(value: Int) -> Style {
  raw("lineHeight", value)
}

pub fn shadow_radius(value: Int) -> Style {
  raw("shadowRadius", value)
}

pub fn min_height(value: Int) -> Style {
  raw("minHeight", value)
}

pub fn z_index(value: Int) -> Style {
  raw("zIndex", value)
}

pub fn top(value: Int) -> Style {
  raw("top", value)
}

pub fn left(value: Int) -> Style {
  raw("left", value)
}

pub fn right(value: Int) -> Style {
  raw("right", value)
}

pub fn bottom(value: Int) -> Style {
  raw("bottom", value)
}

pub fn flex(value: Int) -> Style {
  raw("flex", value)
}

pub fn flex_grow(value: Int) -> Style {
  raw("flexGrow", value)
}

pub fn min_width(value: Int) -> Style {
  raw("minWidth", value)
}

pub fn opacity(value: Float) -> Style {
  raw("opacity", value)
}

pub fn shadow_opacity(value: Float) -> Style {
  raw("shadowOpacity", value)
}

pub fn letter_spacing(value: Float) -> Style {
  raw("letterSpacing", value)
}

pub fn width_pct(value: String) -> Style {
  raw("width", value)
}

pub fn height_pct(value: String) -> Style {
  raw("height", value)
}

pub fn max_width_pct(value: String) -> Style {
  raw("maxWidth", value)
}

pub fn left_pct(value: String) -> Style {
  raw("left", value)
}

pub fn flex_basis_pct(value: String) -> Style {
  raw("flexBasis", value)
}

pub fn width(value: Int) -> Style {
  raw("width", value)
}

pub fn max_width(value: Int) -> Style {
  raw("maxWidth", value)
}

pub fn margin_left_auto() -> Style {
  raw("marginLeft", "auto")
}

/// Fills the parent, like `inset: 0`.
pub fn fill() -> Style {
  raw("inset", 0)
}

@external(javascript, "./style_ffi.mjs", "tabular_nums")
pub fn tabular_nums() -> Style

pub fn shadow_offset(width: Int, height: Int) -> Style {
  raw("shadowOffset", offset(width, height))
}

@external(javascript, "./style_ffi.mjs", "scale")
pub fn scale(value: Float) -> Style

type Offset

@external(javascript, "./style_ffi.mjs", "offset")
fn offset(width: Int, height: Int) -> Offset

@external(javascript, "./style_ffi.mjs", "translate_x")
pub fn translate_x(value: a) -> Style
