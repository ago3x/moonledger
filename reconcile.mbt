///|
pub(all) struct SourceRow {
  file : String
  record : Int
  line : Int
  values : Map[String, String]
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct FieldDelta {
  column : String
  left : String
  right : String
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct Difference {
  kind : String
  key : String
  left : Array[SourceRow]
  right : Array[SourceRow]
  fields : Array[FieldDelta]
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct Counts {
  left_rows : Int
  right_rows : Int
  equal_keys : Int
  changed_keys : Int
  left_only_keys : Int
  right_only_keys : Int
  duplicate_keys : Int
} derive(Eq, @debug.Debug, ToJson)

///|
pub(all) struct Report {
  schema : String
  status : String
  key_column : String
  amount_columns : Array[String]
  counts : Counts
  differences : Array[Difference]
} derive(Eq, @debug.Debug, ToJson)

///|
priv struct IndexedTable {
  headers : Array[String]
  groups : Map[String, Array[SourceRow]]
  rows : Int
}

///|
fn index_csv(
  text : String,
  file : String,
  key_column : String,
  amounts : Array[String],
) -> Result[IndexedTable, LedgerError] {
  let rows = match parse_csv(text, file) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let headers = rows[0].values
  let header_set : Map[String, Bool] = Map([])
  for h in headers {
    if h.trim().is_empty() {
      return Err(
        diagnostic("empty_header", file, 1, 1, "Header names must not be empty"),
      )
    }
    if header_set.contains(h) {
      return Err(
        diagnostic("duplicate_header", file, 1, 1, "Duplicate header: " + h),
      )
    }
    header_set[h] = true
  }
  if !header_set.contains(key_column) {
    return Err(
      diagnostic(
        "missing_key_column",
        file,
        1,
        1,
        "Key column not found: " + key_column,
      ),
    )
  }
  for a in amounts {
    if !header_set.contains(a) {
      return Err(
        diagnostic(
          "missing_amount_column",
          file,
          1,
          1,
          "Amount column not found: " + a,
        ),
      )
    }
  }
  let groups : Map[String, Array[SourceRow]] = Map([])
  for i = 1; i < rows.length(); i = i + 1 {
    let row = rows[i]
    if row.values.length() != headers.length() {
      return Err(
        diagnostic(
          "column_count",
          file,
          row.record,
          row.line,
          "Record width differs from header",
        ),
      )
    }
    let values : Map[String, String] = Map([])
    for j = 0; j < headers.length(); j = j + 1 {
      values[headers[j]] = row.values[j]
    }
    let key = values.get_or_default(key_column, "")
    if key.trim().is_empty() {
      return Err(
        diagnostic(
          "empty_key",
          file,
          row.record,
          row.line,
          "Business key must not be empty",
        ),
      )
    }
    for amount in amounts {
      if canonical_decimal(values.get_or_default(amount, "")) is None {
        return Err(
          diagnostic(
            "invalid_decimal",
            file,
            row.record,
            row.line,
            "Invalid decimal in column: " + amount,
          ),
        )
      }
    }
    let source : SourceRow = {
      file,
      record: row.record,
      line: row.line,
      values,
    }
    match groups.get(key) {
      Some(bucket) => bucket.push(source)
      None => groups[key] = [source]
    }
  }
  Ok({ headers, groups, rows: rows.length() - 1, })
}

///|
/// Reconcile by one exact business key. Column sets must match, order may differ.
/// Invalid input is an error; duplicate groups are isolated on both sides.
pub fn reconcile(
  left_text : String,
  right_text : String,
  left_file : String,
  right_file : String,
  key_column : String,
  amount_columns : Array[String],
) -> Result[Report, LedgerError] {
  let amount_set : Map[String, Bool] = Map([])
  for amount in amount_columns {
    if amount == key_column || amount_set.contains(amount) {
      return Err(
        diagnostic(
          "invalid_amount_option", "", 0, 0, "Amount columns must be unique and different from the key",
        ),
      )
    }
    amount_set[amount] = true
  }
  let left = match index_csv(left_text, left_file, key_column, amount_columns) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let right = match
    index_csv(right_text, right_file, key_column, amount_columns) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  if left.headers.length() != right.headers.length() ||
    !left.headers.all(h => right.headers.contains(h)) {
    return Err(
      diagnostic(
        "schema_mismatch", right_file, 1, 1, "Both files must have the same set of column names",
      ),
    )
  }
  let all_keys : Map[String, Bool] = Map([])
  for key, _ in left.groups {
    all_keys[key] = true
  }
  for key, _ in right.groups {
    all_keys[key] = true
  }
  let keys = all_keys.keys().to_array()
  keys.sort()
  let differences : Array[Difference] = []
  let mut equal_keys = 0
  let mut changed_keys = 0
  let mut left_only_keys = 0
  let mut right_only_keys = 0
  let mut duplicate_keys = 0
  for key in keys {
    let l = left.groups.get_or_default(key, [])
    let r = right.groups.get_or_default(key, [])
    if l.length() > 1 || r.length() > 1 {
      duplicate_keys += 1
      differences.push({
        kind: "duplicate",
        key,
        left: l,
        right: r,
        fields: [],
      })
    } else if l.is_empty() {
      right_only_keys += 1
      differences.push({
        kind: "right_only",
        key,
        left: l,
        right: r,
        fields: [],
      })
    } else if r.is_empty() {
      left_only_keys += 1
      differences.push({
        kind: "left_only",
        key,
        left: l,
        right: r,
        fields: [],
      })
    } else {
      let fields : Array[FieldDelta] = []
      for column in left.headers {
        let lv = l[0].values.get_or_default(column, "")
        let rv = r[0].values.get_or_default(column, "")
        let same = if amount_set.contains(column) {
          canonical_decimal(lv) == canonical_decimal(rv)
        } else {
          lv == rv
        }
        if !same {
          fields.push({ column, left: lv, right: rv, })
        }
      }
      if fields.is_empty() {
        equal_keys += 1
      } else {
        changed_keys += 1
        differences.push({ kind: "changed", key, left: l, right: r, fields, })
      }
    }
  }
  Ok({
    schema: "moonledger.report/1",
    status: if differences.is_empty() {
      "equal"
    } else {
      "differences"
    },
    key_column,
    amount_columns,
    counts: {
      left_rows: left.rows,
      right_rows: right.rows,
      equal_keys,
      changed_keys,
      left_only_keys,
      right_only_keys,
      duplicate_keys,
    },
    differences,
  })
}
