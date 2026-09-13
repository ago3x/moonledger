///|
/// Host functions perform bounded local IO only. Reconciliation stays in MoonBit.
extern "js" fn read_input(path : String) -> String =
  #| (path) => globalThis.moonledgerHost.readInput(path)

///|
extern "js" fn finish(json : String, summary : String, code : Int) -> Unit =
  #| (json, summary, code) => globalThis.moonledgerHost.finish(json, summary, code)

///|
fn usage_error(message : String) -> Unit {
  let error : @lib.LedgerError = {
    code: "usage",
    file: "",
    record: 0,
    line: 0,
    message,
  }
  finish(
    Json::object({ "schema": "moonledger.error/1", "error": error.to_json() }).stringify(),
    message,
    2,
  )
}

///|
fn main {
  let args = @env.args()
  let mut left_file = ""
  let mut right_file = ""
  let mut key = ""
  let amounts : Array[String] = []
  let mut i = 2
  while i < args.length() {
    let option = args[i]
    if option == "--help" || option == "-h" {
      finish(
        "", "MoonLedger 0.1.0\nUsage: node bin/moonledger.cjs --left LEFT.csv --right RIGHT.csv --key COLUMN [--amount COLUMN ...]\nstdout: JSON; stderr: summary. Exit 0=equal, 1=differences, 2=invalid input.\nLocal UTF-8 CSV only; each input at most 8 MiB.",
        0,
      )
      return
    }
    if i + 1 >= args.length() {
      usage_error("Missing value for " + option)
      return
    }
    let value = args[i + 1]
    match option {
      "--left" => {
        if left_file != "" {
          usage_error("--left supplied twice")
          return
        }
        left_file = value
      }
      "--right" => {
        if right_file != "" {
          usage_error("--right supplied twice")
          return
        }
        right_file = value
      }
      "--key" => {
        if key != "" {
          usage_error("--key supplied twice")
          return
        }
        key = value
      }
      "--amount" => amounts.push(value)
      _ => {
        usage_error("Unknown option: " + option)
        return
      }
    }
    i += 2
  }
  if left_file == "" || right_file == "" || key == "" {
    usage_error("--left, --right and --key are required")
    return
  }
  // IO and UTF-8 errors are caught by the small Node entry point.
  let left = read_input(left_file)
  let right = read_input(right_file)
  match @lib.reconcile(left, right, left_file, right_file, key, amounts) {
    Err(error) =>
      finish(
        Json::object({
          "schema": "moonledger.error/1",
          "error": error.to_json(),
        }).stringify(),
        error.code + ": " + error.message,
        2,
      )
    Ok(report) => {
      let c = report.counts
      let summary = "equal=\{c.equal_keys} changed=\{c.changed_keys} left_only=\{c.left_only_keys} right_only=\{c.right_only_keys} duplicate_groups=\{c.duplicate_keys}"
      finish(
        report.to_json().stringify(indent=2),
        summary,
        if report.status == "equal" {
          0
        } else {
          1
        },
      )
    }
  }
}
