"""Copy existing Mac vector data for the independent Windows renderer; never rewrite Mac assets."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = (root / "Sources/DevDeckUI/BrandMark.swift").read_text()
marks = {name: re.search(r'private let ' + name + r'Path = """(.*?)"""', source, re.S).group(1).strip()
         for name in ("github", "gitlab", "node", "next")}
marks["ddev"] = re.findall(r'"""(.*?)"""', source.split("private let ddevPaths = [", 1)[1], re.S)
(root / "Windows/DevDeck.Windows.App/BrandMarks.json").write_text(json.dumps(marks, indent=2) + "\n")
