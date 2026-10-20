#!/usr/bin/env python3
"""Gera Assets/Assets.xcassets/Colors/<token>.colorset a partir de Design/tokens.json (claro + escuro).

Uso: python3 FinanceApp/scripts/gen-colorsets.py
Os nomes batem com os Color Sets usados em App/Design/Tokens.swift. Rode de novo sempre que tokens.json mudar.
"""
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[2]
tokens = json.loads((ROOT / "Design" / "tokens.json").read_text(encoding="utf-8"))
OUT = ROOT / "FinanceApp" / "Assets" / "Assets.xcassets" / "Colors"


def cap(s: str) -> str:
    return s[:1].upper() + s[1:]


def collect():
    colors = {}
    c = tokens["color"]
    for name, v in c["background"].items():
        colors[name] = v
    for name, v in c["text"].items():
        colors["text" + cap(name)] = v
    for name, v in c["line"].items():
        colors[name] = v
    for name, v in c["brand"].items():
        colors["brand" + cap(name)] = v
    colors["focus"] = c["focus"]
    for name, v in c["semantic"].items():
        colors[name] = v
    for name, v in c["category"].items():
        if isinstance(v, dict) and "light" in v:
            colors["cat" + cap(name)] = v
    return colors


def component(hex_value: str):
    # Componentes em hexadecimal de 8 bits ("0xEE"): exatos, sem erro de arredondamento do ponto flutuante.
    h = hex_value.lstrip("#").upper()
    return {"alpha": "1.000", "red": "0x" + h[0:2], "green": "0x" + h[2:4], "blue": "0x" + h[4:6]}


def entry(hex_value: str, dark: bool):
    e = {"color": {"color-space": "srgb", "components": component(hex_value)}, "idiom": "universal"}
    if dark:
        e["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
    return e


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    colors = collect()
    for name, v in colors.items():
        d = OUT / f"{name}.colorset"
        d.mkdir()
        contents = {"colors": [entry(v["light"], False), entry(v["dark"], True)], "info": {"author": "xcode", "version": 1}}
        (d / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(f"{len(colors)} color sets em {OUT}")
    print(" ".join(sorted(colors)))


if __name__ == "__main__":
    main()
