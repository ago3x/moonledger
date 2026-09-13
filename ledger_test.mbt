///|
fn parsed(text : String) -> Array[@moonledger.CsvRecord] {
  match @moonledger.parse_csv(text, "fixture.csv") {
    Ok(rows) => rows
    Err(e) => abort(e.message)
  }
}

///|
fn compared(
  left : String,
  right : String,
  amounts? : Array[String] = [],
) -> @moonledger.Report {
  match
    @moonledger.reconcile(left, right, "left.csv", "right.csv", "id", amounts) {
    Ok(report) => report
    Err(e) => abort(e.message)
  }
}

///|
test "CSV quoted commas and escaped quotes" {
  let r = parsed("id,note\n1,\"a,b and \"\"quote\"\"\"\n")
  assert_eq(r.length(), 2)
  assert_eq(r[1].values, ["1", "a,b and \"quote\""])
}

///|
test "CSV Unicode and initial BOM" {
  let r = parsed("﻿id,note\n订单😀,你好\n")
  assert_eq(r[0].values, ["id", "note"])
  assert_eq(r[1].values, ["订单😀", "你好"])
}

///|
test "CSV multiline CRLF provenance" {
  let r = parsed("id,note\r\n1,\"line1\r\nline2\"\r\n2,last\r\n")
  assert_eq(r[1].values[1], "line1\r\nline2")
  assert_eq(r[1].record, 2)
  assert_eq(r[1].line, 2)
  assert_eq(r[2].record, 3)
  assert_eq(r[2].line, 4)
}

///|
test "CSV mixed physical newlines" {
  let r = parsed("id,note\r1,\"a\nb\rc\"\n2,z")
  assert_eq(r[1].line, 2)
  assert_eq(r[2].line, 5)
  assert_eq(r[1].values[1], "a\nb\rc")
}

///|
test "CSV empty fields and trailing comma" {
  assert_eq(parsed("a,b,c\n,,")[1].values, ["", "", ""])
  assert_eq(parsed("a,b\n1,\n").length(), 2)
  assert_eq(parsed("a,b\n1,\"\"")[1].values, ["1", ""])
}

///|
test "CSV blank records are preserved" {
  let rows = parsed("a\n\nx\n")
  assert_eq(rows.length(), 3)
  assert_eq(rows[1].values, [""])
  assert_eq(rows[2].line, 3)
}

///|
test "CSV rejects malformed quoting and empty input" {
  for
    (text, code) in [
      ("", "empty_csv"),
      ("﻿", "empty_csv"),
      ("a\nx\"y", "unexpected_quote"),
      ("a\n\"x\"z", "after_quote"),
      ("a\n\"x", "unclosed_quote"),
      ("a\n\"x\" ", "after_quote"),
    ] {
    match @moonledger.parse_csv(text, "bad.csv") {
      Ok(_) => abort("Malformed CSV was accepted")
      Err(e) => {
        assert_eq(e.code, code)
        assert_eq(e.file, "bad.csv")
      }
    }
  }
}

///|
test "decimal sign zero and normalization" {
  assert_eq(@moonledger.canonical_decimal("+00012.3400"), Some("12.34"))
  assert_eq(@moonledger.canonical_decimal("-000.000"), Some("0"))
  assert_eq(@moonledger.canonical_decimal("-00012.01"), Some("-12.01"))
  assert_eq(@moonledger.canonical_decimal("0"), Some("0"))
}

///|
test "decimal precision beyond double and int64" {
  let a = "999999999999999999999999999999.123456789123456789"
  assert_eq(@moonledger.canonical_decimal(a + "0"), Some(a))
  assert_true(
    @moonledger.canonical_decimal("9007199254740992.01") !=
    @moonledger.canonical_decimal("9007199254740992.02"),
  )
}

///|
test "decimal rejects ambiguous formats" {
  for
    input in [
      "", "+", "-", ".1", "1.", "1e3", "NaN", "Infinity", " 1", "1 ", "1,000", "￥1",
      "1.2.3", "１２",
    ] {
    assert_eq(@moonledger.canonical_decimal(input), None)
  }
  assert_eq(@moonledger.canonical_decimal(String::make(257, '1')), None)
  assert_true(@moonledger.canonical_decimal(String::make(256, '1')) is Some(_))
}

///|
test "reconciliation ignores row and column ordering" {
  let r = compared("id,note\n2,b\n1,a", "note,id\na,1\nb,2")
  assert_eq(r.status, "equal")
  assert_eq(r.counts.equal_keys, 2)
  assert_eq(r.differences.length(), 0)
}

///|
test "amount comparison is opt-in" {
  let l = "id,amount\n1,00012.340"
  let r = "id,amount\n1,+12.34"
  assert_eq(compared(l, r).counts.changed_keys, 1)
  assert_eq(compared(l, r, amounts=["amount"]).counts.equal_keys, 1)
}

///|
test "all difference types and exact source values" {
  let l = "id,amount\nA,1\nB,2\nD,3\nD,4"
  let r = "id,amount\nB,2.01\nC,5\nD,3"
  let out = compared(l, r, amounts=["amount"])
  assert_eq(out.counts.left_rows, 4)
  assert_eq(out.counts.right_rows, 3)
  assert_eq(out.counts.left_only_keys, 1)
  assert_eq(out.counts.right_only_keys, 1)
  assert_eq(out.counts.changed_keys, 1)
  assert_eq(out.counts.duplicate_keys, 1)
  assert_eq(out.differences.map(d => d.key), ["A", "B", "C", "D"])
  let change = out.differences[1]
  assert_eq(change.fields[0].column, "amount")
  assert_eq(change.fields[0].left, "2")
  assert_eq(change.fields[0].right, "2.01")
  assert_eq(change.left[0].line, 3)
  assert_eq(change.right[0].line, 2)
  assert_eq(out.differences[3].left.length(), 2)
  assert_eq(out.differences[3].right.length(), 1)
  assert_eq(out.differences[3].fields.length(), 0)
}

///|
test "right and bilateral duplicates never become ordinary matches" {
  let l = "id,v\nA,1"
  let r = "id,v\nA,1\nA,1"
  assert_eq(compared(l, r).counts.duplicate_keys, 1)
  assert_eq(compared(r, r).counts.equal_keys, 0)
  assert_eq(compared(r, "id,v").differences[0].kind, "duplicate")
}

///|
test "keys preserve whitespace and zeroes" {
  let out = compared("id,v\n01,a\n1,b\n 1,c", "id,v\n1,b\n 1,c\n01,a")
  assert_eq(out.counts.equal_keys, 3)
}

///|
test "header-only inputs are valid empty tables" {
  let r = compared("id,v", "id,v\n")
  assert_eq(r.status, "equal")
  assert_eq(r.counts.left_rows, 0)
}

///|
test "schema and row diagnostics identify source" {
  for
    (input, code) in [
      ("id,id\n1,2", "duplicate_header"),
      ("id,\n1,2", "empty_header"),
      ("other,v\n1,2", "missing_key_column"),
      ("id,v\n1", "column_count"),
      ("id,v\n1,2,3", "column_count"),
      ("id,v\n,2", "empty_key"),
      ("id,v\n  ,2", "empty_key"),
    ] {
    match
      @moonledger.reconcile(input, "id,v\n1,2", "invalid.csv", "r.csv", "id", []) {
      Ok(_) => abort("Invalid input was accepted")
      Err(e) => {
        assert_eq(e.code, code)
        assert_eq(e.file, "invalid.csv")
      }
    }
  }
  match @moonledger.reconcile("id,a", "id,b", "l", "r", "id", []) {
    Err(e) => assert_eq(e.code, "schema_mismatch")
    Ok(_) => abort("Mismatched schemas were accepted")
  }
}

///|
test "invalid decimals are rejected even in duplicate or unmatched rows" {
  for input in ["id,v\nA,bad", "id,v\nA,1\nA,bad"] {
    match @moonledger.reconcile(input, "id,v", "l", "r", "id", ["v"]) {
      Err(e) => assert_eq(e.code, "invalid_decimal")
      Ok(_) => abort("Invalid decimal was silently hidden")
    }
  }
}

///|
test "amount options are validated" {
  for
    (amounts, code) in [
      (["id"], "invalid_amount_option"),
      (["v", "v"], "invalid_amount_option"),
      (["missing"], "missing_amount_column"),
    ] {
    match @moonledger.reconcile("id,v", "id,v", "l", "r", "id", amounts) {
      Err(e) => assert_eq(e.code, code)
      Ok(_) => abort("Invalid amount option was accepted")
    }
  }
}

///|
test "multiline values retain exact mismatch provenance" {
  let r = compared("id,v\nA,\"one\ntwo\"\nB,old", "id,v\nB,new\nA,\"one\ntwo\"")
  assert_eq(r.counts.equal_keys, 1)
  assert_eq(r.differences[0].key, "B")
  assert_eq(r.differences[0].left[0].record, 3)
  assert_eq(r.differences[0].left[0].line, 4)
}
