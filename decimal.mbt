///|
/// Canonical decimal: optional sign, digits, optional nonempty fraction.
/// No floating point, rounding, exponent, separators or whitespace.
/// Maximum 256 input characters.
pub fn canonical_decimal(input : String) -> String? {
  let chars = input.to_array()
  if chars.is_empty() || chars.length() > 256 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if chars[0] == '-' || chars[0] == '+' {
    negative = chars[0] == '-'
    i = 1
  }
  let integer_start = i
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    i += 1
  }
  if i == integer_start {
    return None
  }
  let integer_end = i
  let mut fraction_start = i
  let mut fraction_end = i
  if i < chars.length() {
    if chars[i] != '.' {
      return None
    }
    i += 1
    fraction_start = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      i += 1
    }
    if i == fraction_start {
      return None
    }
    fraction_end = i
  }
  if i != chars.length() {
    return None
  }
  let mut first = integer_start
  while first < integer_end - 1 && chars[first] == '0' {
    first += 1
  }
  while fraction_end > fraction_start && chars[fraction_end - 1] == '0' {
    fraction_end -= 1
  }
  let zero = first == integer_end - 1 &&
    chars[first] == '0' &&
    fraction_end == fraction_start
  let out = StringBuilder()
  if negative && !zero {
    out.write_char('-')
  }
  for j = first; j < integer_end; j = j + 1 {
    out.write_char(chars[j])
  }
  if fraction_end > fraction_start {
    out.write_char('.')
    for j = fraction_start; j < fraction_end; j = j + 1 {
      out.write_char(chars[j])
    }
  }
  Some(out.to_string())
}
