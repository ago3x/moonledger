///|
pub(all) struct CsvRecord {
  record : Int
  line : Int
  values : Array[String]
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct LedgerError {
  code : String
  file : String
  record : Int
  line : Int
  message : String
} derive(Eq, @debug.Debug, ToJson)

///|
fn diagnostic(
  code : String,
  file : String,
  record : Int,
  line : Int,
  message : String,
) -> LedgerError {
  { code, file, record, line, message, }
}

///|
/// Strict CSV: comma delimiter, LF/CRLF/CR, optional leading BOM.
/// Whitespace and blank records are preserved.
pub fn parse_csv(
  text : String,
  file : String,
) -> Result[Array[CsvRecord], LedgerError] {
  if text.length() > 8 * 1024 * 1024 {
    return Err(
      diagnostic(
        "input_too_large", file, 0, 0, "CSV exceeds the 8 Mi UTF-16-unit library limit",
      ),
    )
  }
  let chars = text.to_array()
  let mut i = if chars.length() > 0 && chars[0].to_int() == 0xFEFF {
    1
  } else {
    0
  }
  let rows : Array[CsvRecord] = []
  let mut fields : Array[String] = []
  let field = StringBuilder()
  let mut state = 0 // field start, unquoted, quoted, after quote
  let mut line = 1
  let mut start_line = 1
  let mut touched = false
  while i < chars.length() {
    let c = chars[i]
    touched = true
    if state == 2 {
      if c == '"' {
        if i + 1 < chars.length() && chars[i + 1] == '"' {
          field.write_char('"')
          i += 2
          continue
        }
        state = 3
      } else {
        field.write_char(c)
        if c == '\r' {
          if i + 1 < chars.length() && chars[i + 1] == '\n' {
            field.write_char('\n')
            i += 1
          }
          line += 1
        } else if c == '\n' {
          line += 1
        }
      }
    } else if c == ',' {
      if fields.length() >= 255 {
        return Err(
          diagnostic(
            "too_many_columns",
            file,
            rows.length() + 1,
            start_line,
            "CSV allows at most 256 columns",
          ),
        )
      }
      fields.push(field.to_string())
      field.reset()
      state = 0
    } else if c == '\n' || c == '\r' {
      if rows.length() >= 100001 {
        return Err(
          diagnostic(
            "too_many_records",
            file,
            rows.length() + 1,
            start_line,
            "CSV allows at most 100000 data records",
          ),
        )
      }
      fields.push(field.to_string())
      rows.push({ record: rows.length() + 1, line: start_line, values: fields, })
      fields = []
      field.reset()
      state = 0
      touched = false
      if c == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
        i += 1
      }
      line += 1
      start_line = line
    } else if c == '"' {
      if state != 0 {
        return Err(
          diagnostic(
            "unexpected_quote",
            file,
            rows.length() + 1,
            line,
            "Quote inside an unquoted field",
          ),
        )
      }
      state = 2
    } else {
      if state == 3 {
        return Err(
          diagnostic(
            "after_quote",
            file,
            rows.length() + 1,
            line,
            "Expected comma or newline after closing quote",
          ),
        )
      }
      field.write_char(c)
      state = 1
    }
    i += 1
  }
  if state == 2 {
    return Err(
      diagnostic(
        "unclosed_quote",
        file,
        rows.length() + 1,
        start_line,
        "Quoted field is not closed",
      ),
    )
  }
  if touched || fields.length() > 0 {
    if rows.length() >= 100001 {
      return Err(
        diagnostic(
          "too_many_records",
          file,
          rows.length() + 1,
          start_line,
          "CSV allows at most 100000 data records",
        ),
      )
    }
    fields.push(field.to_string())
    rows.push({ record: rows.length() + 1, line: start_line, values: fields, })
  }
  if rows.is_empty() {
    return Err(diagnostic("empty_csv", file, 0, 1, "CSV needs a header record"))
  }
  Ok(rows)
}
