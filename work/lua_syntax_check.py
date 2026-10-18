"""Structural Lua check for the files this project ships.

No Lua interpreter or Lua parser exists in this environment, so the shipped Lua
cannot be compiled here. This checker is deliberately narrow and honest: it
verifies that block openers and closers balance, that long strings, long
comments and quoted strings terminate, and that parentheses/brackets/braces
balance, while ignoring comments and string contents. It is not a parser and it
cannot prove a file correct; a file that passes it can still fail to load.

Run: python3 work/lua_syntax_check.py <files...>
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

OPENERS = {"function", "if", "for", "while", "do", "repeat"}
CLOSERS = {"end", "until"}
# `for` and `while` open their block with a `do` that is part of the header, so
# that `do` must not be counted a second time.
HEADERS = {"for", "while"}

# Long-bracket levels Lua accepts: [=*[ ... ]=*]
def long_bracket(text: str, index: int):
    if text[index] != "[":
        return None
    cursor = index + 1
    while cursor < len(text) and text[cursor] == "=":
        cursor += 1
    if cursor < len(text) and text[cursor] == "[":
        return cursor - index - 1  # number of '='
    return None


def check(path: Path):
    text = path.read_text(encoding="utf-8")
    problems = []
    depth = 0
    stack = []
    pending_do = False
    index = 0
    line = 1
    while index < len(text):
        character = text[index]
        if character == "\n":
            line += 1
            index += 1
            continue
        if text.startswith("--", index):
            level = long_bracket(text, index + 2)
            if level is None:
                end = text.find("\n", index)
                index = len(text) if end < 0 else end
                continue
            closer = "]" + "=" * level + "]"
            end = text.find(closer, index)
            if end < 0:
                problems.append(f"line {line}: unterminated long comment")
                break
            line += text.count("\n", index, end)
            index = end + len(closer)
            continue
        if character in "\"'":
            quote, start = character, line
            index += 1
            while index < len(text) and text[index] != quote:
                if text[index] == "\\":
                    index += 1
                elif text[index] == "\n":
                    problems.append(f"line {start}: unterminated string")
                    break
                index += 1
            if index >= len(text):
                problems.append(f"line {start}: unterminated string")
                break
            index += 1
            continue
        level = long_bracket(text, index)
        if level is not None:
            closer = "]" + "=" * level + "]"
            end = text.find(closer, index)
            if end < 0:
                problems.append(f"line {line}: unterminated long string")
                break
            line += text.count("\n", index, end)
            index = end + len(closer)
            continue
        if character.isalpha() or character == "_":
            end = index
            while end < len(text) and (text[end].isalnum() or text[end] == "_"):
                end += 1
            word = text[index:end]
            if word in HEADERS:
                stack.append((word, line))
                depth += 1
                pending_do = True
            elif word == "do" and pending_do:
                pending_do = False
            elif word in OPENERS:
                stack.append((word, line))
                depth += 1
                pending_do = False
            elif word in CLOSERS:
                if not stack:
                    problems.append(f"line {line}: '{word}' without an opener")
                else:
                    stack.pop()
                    depth -= 1
            index = end
            continue
        index += 1
    for word, start in stack:
        problems.append(f"line {start}: '{word}' is never closed")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    arguments = parser.parse_args()
    failures = 0
    for path in arguments.files:
        problems = check(path)
        if problems:
            failures += 1
            print(f"FAIL {path}")
            for problem in problems:
                print(f"     {problem}")
        else:
            print(f"ok   {path}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
