#!/usr/bin/env python3
"""Independent CLI checks; only synthetic temporary files are used."""
from pathlib import Path
from collections import defaultdict
from decimal import Decimal
import csv, io, json, subprocess, tempfile, random, hashlib, os

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "bin/moonledger.cjs"
NODE = os.environ.get("NODE", "node")
rng = random.Random(20260913)
checks = 0
random_cases = 60

def run(*args):
    return subprocess.run([NODE, str(CLI), *map(str, args)], cwd=ROOT,
                          text=True, capture_output=True, timeout=15)

def report(left, right, *options):
    result = run("--left", left, "--right", right, "--key", "id", *options)
    assert result.returncode in (0, 1, 2), result.stderr
    try:
        parsed = json.loads(result.stdout)
    except Exception as e:
        raise AssertionError((result.returncode, result.stdout, result.stderr)) from e
    return result, parsed

def expect_error(left, right, code, *options):
    global checks
    result, doc = report(left, right, *options)
    assert result.returncode == 2, result
    assert doc["schema"] == "moonledger.error/1", doc
    assert doc["error"]["code"] == code, doc
    checks += 1

def write_csv(path, rows, columns=("id","amount","note"), newline="\r\n", bom=False):
    buf = io.StringIO(newline="")
    writer = csv.DictWriter(buf, fieldnames=columns, lineterminator=newline)
    writer.writeheader()
    writer.writerows(rows)
    path.write_bytes((("\ufeff" if bom else "")+buf.getvalue()).encode())

def oracle(path):
    # Python's CSV reader is independent of the MoonBit state machine.
    text=path.read_bytes().decode("utf-8-sig")
    reader=csv.reader(io.StringIO(text, newline=""))
    headers=next(reader)
    groups=defaultdict(list)
    record=1
    while True:
        start=reader.line_num+1
        try: values=next(reader)
        except StopIteration: break
        record+=1
        row=dict(zip(headers,values))
        groups[row["id"]].append({"file":str(path),"record":record,"line":start,"values":row})
    return headers,groups

with tempfile.TemporaryDirectory(prefix="moonledger-test-") as td:
    tmp=Path(td); left=tmp/"left.csv"; right=tmp/"right.csv"
    left.write_text("id,amount,note\nA,1,x\n")
    right.write_text("note,id,amount\nx,A,1.00\n")
    result, doc=report(left,right,"--amount","amount")
    assert result.returncode==0 and doc["counts"]["equal_keys"]==1
    checks+=1
    result, doc=report(ROOT/"examples/left.csv", ROOT/"examples/right.csv","--amount","amount")
    assert result.returncode==1 and doc["counts"]=={
        "left_rows":6,"right_rows":5,"equal_keys":2,"changed_keys":1,
        "left_only_keys":1,"right_only_keys":1,"duplicate_keys":1}
    assert [(d["key"],d["kind"]) for d in doc["differences"]]==[
        ("B","changed"),("C","left_only"),("D","duplicate"),("E","right_only")]
    assert doc["differences"][0]["right"][0]["record"]==4
    assert doc["differences"][0]["right"][0]["line"]==5
    checks+=1

    before=(hashlib.sha256(left.read_bytes()).hexdigest(),hashlib.sha256(right.read_bytes()).hexdigest())
    first=report(left,right,"--amount","amount")[0]
    second=report(left,right,"--amount","amount")[0]
    assert first.stdout==second.stdout and before==(
        hashlib.sha256(left.read_bytes()).hexdigest(),hashlib.sha256(right.read_bytes()).hexdigest())
    checks+=1
    for args in [[],["--left"],["--unknown","x"],["--left",left,"--left",left]]:
        result=run(*args); assert result.returncode==2 and json.loads(result.stdout)["error"]["code"]=="usage"
        checks+=1
    assert run("--help").returncode==0
    checks+=1
    expect_error(tmp/"missing.csv",right,"ENOENT")
    expect_error(tmp,right,"not_regular_file")
    if hasattr(os,"mkfifo"):
        fifo=tmp/"pipe.csv"; os.mkfifo(fifo)
        expect_error(fifo,right,"not_regular_file")
    left.write_bytes(b"id,amount,note\nA,1,\xff\n")
    expect_error(left,right,"invalid_utf8")
    with left.open("wb") as f: f.truncate(8*1024*1024+1)
    expect_error(left,right,"input_too_large")
    left.write_text("id,amount,note\nA,bad,x")
    expect_error(left,right,"invalid_decimal","--amount","amount")
    left.write_text("id,amount,note\nA,1,x")
    expect_error(left,right,"invalid_amount_option","--amount","id")
    expect_error(left,right,"invalid_amount_option","--amount","amount","--amount","amount")
    expect_error(left,right,"missing_amount_column","--amount","absent")
    left.write_text(",".join(["id"]+[f"c{i}" for i in range(256)]))
    expect_error(left,right,"too_many_columns")
    left.write_text("id\n"+"x\n"*100001)
    expect_error(left,right,"too_many_records")

    for iteration in range(random_cases):
        rows=[]
        notes=["plain","comma,inside",'say "hi"',"multi\nline","多行😀\r\n结束","", "  spaces  "]
        for k in range(rng.randrange(2,20)):
            rows.append({"id":f"K{k:03}","amount":f"{rng.randrange(-99999,99999)}.{rng.randrange(100):02}",
                         "note":rng.choice(notes)})
        lrows=[dict(r) for r in rows if rng.random()>.15]
        rrows=[dict(r) for r in rows if rng.random()>.15]
        for row in rrows:
            row["amount"]+="00"  # numeric equality despite representation
            if rng.random()<.2: row["amount"]=str(Decimal(row["amount"])+Decimal("0.000000000000001"))
            if rng.random()<.2: row["note"]+="changed"
        if lrows and rng.random()<.7: lrows.append(dict(rng.choice(lrows)))
        if rrows and rng.random()<.7: rrows.append(dict(rng.choice(rrows)))
        rng.shuffle(lrows); rng.shuffle(rrows)
        write_csv(left,lrows,bom=iteration%2==0)
        write_csv(right,rrows,columns=("note","id","amount"))
        result, actual=report(left,right,"--amount","amount")
        headers,lg=oracle(left); _,rg=oracle(right)
        counts=dict(left_rows=len(lrows),right_rows=len(rrows),equal_keys=0,changed_keys=0,
                    left_only_keys=0,right_only_keys=0,duplicate_keys=0)
        diffs=[]
        for key in sorted(lg.keys()|rg.keys()):
            ls,rs=lg[key],rg[key]; fields=[]
            if len(ls)>1 or len(rs)>1:
                kind="duplicate"; counts["duplicate_keys"]+=1
            elif not ls:
                kind="right_only"; counts["right_only_keys"]+=1
            elif not rs:
                kind="left_only"; counts["left_only_keys"]+=1
            else:
                for col in headers:
                    lv,rv=ls[0]["values"][col],rs[0]["values"][col]
                    equal=Decimal(lv)==Decimal(rv) if col=="amount" else lv==rv
                    if not equal: fields.append({"column":col,"left":lv,"right":rv})
                if not fields: counts["equal_keys"]+=1; continue
                kind="changed"; counts["changed_keys"]+=1
            diffs.append({"kind":kind,"key":key,"left":ls,"right":rs,"fields":fields})
        assert actual["counts"]==counts, (iteration,actual,counts)
        assert actual["differences"]==diffs, (iteration,actual["differences"],diffs)
        assert result.returncode==(1 if diffs else 0)
        checks+=1

print(json.dumps({"status":"passed","cli_checks":checks,"randomized_oracle_cases":random_cases,
                  "random_seed":20260913,"reference":"Python csv.reader and decimal.Decimal",
                  "input_files_modified":False},indent=2))
