#!/usr/bin/env python3
"""Check a built locale ZIP without changing OFS3 source or accessing a radio."""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
from zipfile import ZipFile

from lupa.lua53 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]


def validate(path, locale, version):
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_lua = lua.eval('function(s, name) local fn, err = load(s, name); return fn ~= nil, err end')
    with ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate ZIP members")
        for name in names:
            parts = PurePosixPath(name).parts
            if name.startswith("/") or ".." in parts or "\\" in name or ":" in name:
                raise ValueError(f"Unsafe ZIP member: {name}")
            if not name.startswith("scripts/ofs3/"):
                raise ValueError(f"Unexpected install path: {name}")
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt ZIP member: {bad}")
        for source in (ROOT / "src/ofs3").rglob("*"):
            if source.is_file():
                expected = "scripts/ofs3/" + source.relative_to(ROOT / "src/ofs3").as_posix()
                if expected not in names:
                    raise ValueError(f"Missing source file: {expected}")
        json.loads(archive.read(f"scripts/ofs3/i18n/{locale}.json"))
        main = archive.read("scripts/ofs3/main.lua").decode("utf-8")
        if not re.search(r'suffix\s*=\s*"' + re.escape(version) + r'"', main):
            raise ValueError("Package version suffix does not match the requested version")
        lua_count = 0
        for name in names:
            if name.endswith(".lua"):
                text = archive.read(name).decode("utf-8")
                if "@i18n(" in text:
                    raise ValueError(f"Unresolved translation in {name}")
                ok, error = compile_lua(text, "@" + name)
                if not ok:
                    raise ValueError(error)
                lua_count += 1
        if not lua_count:
            raise ValueError("No Lua files in package")
    print(f"Validated {locale} ZIP: {len(names)} files, {lua_count} Lua modules")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--lang", required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    validate(args.package, args.lang, args.version)
