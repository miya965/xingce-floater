#!/usr/bin/env python3
"""把 Database/schema.sql 写进 Swift 常量，避免两份结构漂移。"""

import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[1]
source = root / "Database" / "schema.sql"
target = root / "Sources" / "XingceCore" / "SchemaSQL.swift"
sql = source.read_text(encoding="utf-8")
if not sql.endswith("\n"):
    sql += "\n"
if '"""' in sql:
    raise SystemExit("schema.sql 不能包含三引号")

# Swift 多行字符串会丢掉结束定界符前的那一个换行，这里补一行空行，使常量与文件字节一致。
literal = sql + "\n"

target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(
    "// Generated from Database/schema.sql. Do not edit by hand.\n"
    "import Foundation\n\n"
    "enum SchemaSQL {\n"
    "    static let text = \"\"\"\n"
    f"{literal}"
    "\"\"\"\n"
    "}\n",
    encoding="utf-8",
)
print(target)
