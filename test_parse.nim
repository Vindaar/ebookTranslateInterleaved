import std/[strutils, sequtils, tables, options, algorithm, json, strformat]
from std / os import walkFiles, extractFilename
import texParser

proc printFile(fname: string) =
  let latex = readFile(fname)
  let parsed = parseTex(latex)

  let (header, doc) = getDocument(parsed)

  for x in doc.content:
    case x.kind
    of txEnvironment:
      echo "Environment: ", x.envName
      if "figure" in x.envName:
        echo "\t", ($x).len
        if ($x).len < 2000:
          echo x
        else:
          echo ($x)[0 .. 1999]
    of txCommand:
      echo "Command: ", x.name
      if "section" in x.name:
        echo "\t", x
    else:
      echo x.kind

  if true: quit()

  echo "Sections of file: ", fname
  var idx = 0
  for s in sections(parsed):
    echo "SECTION::: \n\n"
    echo s
    echo "\n\n================\n\n"

proc main(fname: string = "", dir: string = "") =
  ## testing. Just start with one for now...
  if fname.len > 0:
    printFile(fname)
  else:
    for f in walkFiles(dir):
      printFile(f)


when isMainModule:
  import cligen
  dispatch main
