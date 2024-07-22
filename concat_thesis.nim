import std/[strutils, sequtils, tables, options, algorithm, json, strformat]
from std / os import walkFiles, extractFilename, `/`
import texParser, openai

import std / [xmltree, xmlparser]

proc extractTranslateTag(f: string): string =
  ## Given a `.tex` file with a
  ## `<translate> ... </translate>` tag, extracts it and returns the body
  const Start = r"<translation>"
  const End   = r"</translation>"

  let data = readFile f
  let frm = data.find(Start) + Start.len
  let to  = data.find(End) - 1
  result = data[frm .. to]

proc concatFile(fname, translateDir: string) =
  # 1. parse original file for the header (which we don't translate)
  let latex = readFile(fname)
  let parsed = parseTex(latex)

  let (header, doc) = getDocument(parsed)

  var body = $header
  if doc != nil:
    body.add "\\begin{document}\n"
  # 2. find all files matching `fname` in translateDir
  let dir = translateDir / (fname.extractFilename.replace(".tex", "*.tex"))
  echo "Walking: ", dir
  for f in walkFiles(dir):
    if f.endsWith("_combined.tex"): continue # skip already processed!
    echo "Reading: ", f
    let b = extractTranslateTag(f)
    echo "Adding: "
    echo b
    body.add b
  if doc != nil:
    body.add "\\end{document}\n"
  writeFile(fname.extractFilename.replace(".tex", "_translated_combined.tex"), body)

proc main(dir: string, translateDir: string) =
  ## Argument must be directory to the original files.
  ##
  ## dir must contain a glob for e.g. `*.tex` files
  ##
  ## translateDir must only be a directory, no glob!
  for f in walkFiles(dir):
    echo "Working on file: ", f
    concatFile(f, translateDir)

when isMainModule:
  import cligen
  dispatch main
