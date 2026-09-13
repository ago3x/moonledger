# MoonLedger

按业务键核对两份 CSV，保留原始记录位置，隔离重复键，精确比较小数金额。

例如：订单导出与结算导出的行顺序不同，普通文本 diff 很难看清漏项；某一业务键出现两次时，直接合并又可能隐藏问题。MoonLedger 将正常匹配、字段变化、左右缺失和重复组分开报告。它是核对辅助工具，不自动修改输入或判定账务正确。

## 快速开始

需要 MoonBit 工具链、Node.js 20+；运行测试还需要 Python 3。安装 MoonBit 见[官方说明](https://www.moonbitlang.com/download/)。

```sh
moon build --target js --release
node bin/moonledger.cjs --left examples/left.csv --right examples/right.csv --key id --amount amount
```

示例文件全部为合成数据，不包含客户记录。

示例输出摘要：

```text
equal=2 changed=1 left_only=1 right_only=1 duplicate_groups=1
```

JSON 报告写到 stdout；摘要写到 stderr。退出码 0 表示在所选规则下相同，1 表示发现差异或重复组，2 表示输入或使用错误。示例发现差异，因此退出码为 1；这不是程序崩溃。

使用 shell 重定向可保存结果，例如在上述命令后加 `> report.json`。工具本身不写入文件。请不要将输出重定向到任何输入文件。

## 核对规则

- `--left`、`--right`、`--key` 必填，分别指定两个本地文件和一个业务键列。
- `--amount` 可重复，用于选择需要精确十进制比较的列。未选择的列按原始字符串比较，包括空格和换行。
- 键按完整字符串匹配，不自动去空格、不去前导零、不做大小写转换。纯空白键报错。首期使用单列键。
- 两侧必须有同一组唯一且非空的列名；列顺序可以不同。
- 任意一侧的某个键不唯一，就将这个键两侧的全部记录放进一个 `duplicate` 组，不猜测配对，也不把其中一行计入“相同”。
- 先验证全部输入，再核对。非法金额即使位于重复或单侧记录中也会报错。
- 金额支持可选正负号、整数部分及可选非空小数部分，最长 256 字符。`+0012.3400` 与 `12.34` 相同，负零与零相同。不使用浮点数或舍入。指数、千分位、货币符号和空白不接受。
- 差异组按 MoonBit 字符串比较顺序排序；组内保留原输入记录顺序，字段差异按左表列顺序输出。相同输入和参数产生相同报告。

## CSV 与资源边界

UTF-8、逗号分隔，支持双引号转义、字段内换行、LF/CRLF/CR 及文件开头一个 BOM。空字段、空白记录和字段里的换行保持原样。引号未闭合、未引号字段里出现引号、闭合引号后出现非分隔字符等情况明确报错。

命令行每个输入最多 8 MiB，必须是普通文件。读取无效 UTF-8、目录或管道会返回结构化错误。核心库另限制每份文本 8 Mi UTF-16 单元；最多 256 列、100,000 条数据记录。实现将文件读入内存；不提供流式处理、Excel 解析、编码猜测、模糊匹配、账务汇总或自动修复。

每条来源记录包含：

| 字段 | 含义 |
| --- | --- |
| `file` | 调用方提供的文件名/路径 |
| `record` | 从 1 开始的逻辑 CSV 记录号，表头为 1 |
| `line` | 从 1 开始的物理起始行号，CRLF 算一次换行 |
| `values` | 列名映射到原始文本，金额也保持原始表示 |

成功报告使用 `moonledger.report/1`；错误使用 `moonledger.error/1`，包含 `code/file/record/line/message`。文件级或参数级错误的位置可为 0。计数单位是唯一业务键组，`left_rows/right_rows` 则是数据记录数；它们不是金额或账务结论。

## 实现

主要实现语言是 MoonBit：

- `csv.mbt`：严格 CSV 状态机与来源位置。
- `decimal.mbt`：以字符串规范化精确十进制数。
- `reconcile.mbt`：模式验证、索引、重复组隔离和差异报告。
- `cmd/main/main.mbt`：参数解析和命令行流程。
- `bin/moonledger.cjs`：小型 Node 适配层，只负责限量文件读取、UTF-8 解码和进程输出。所有核对规则均在 MoonBit 中。

核心库仅依赖 MoonBit 标准库；Node 适配层无 npm 依赖，不访问网络。JavaScript 后端是当前验证过的运行目标；不能据此声称原生或其他后端已经验证。

## 验证

```sh
python3 scripts/verify.py
```

脚本依次检查格式和类型、运行 MoonBit 测试、编译实际命令行，然后运行独立的 Python 对照测试。当前覆盖 20 项 MoonBit 测试及 79 项命令行检查；后者包含 60 组固定种子的随机数据，利用 Python `csv.reader` 和 `decimal.Decimal` 独立计算完整期望报告，包含来源行号。还检查错误退出码、非法 UTF-8、容量边界和输入文件未被修改。

最近验证见 [verification/RESULTS.md](verification/RESULTS.md)。已有测试范围不等于比赛验收或奖励资格。

## 来源与许可

本期从头实现 MoonBit 核心、命令行及测试。与此前的模型 CSV 评测、JavaScript 网页演示是不同项目，没有将旧网页更名为参赛成果。部分需求来自同一类表格核对问题，未复制第三方业务实现。

使用 `moon new` 创建基础包布局；MoonBit 标准库使用 Apache-2.0 许可，Node/Python 使用各自许可。本仓库原创代码采用 MIT；详见 [LICENSE](LICENSE)。
