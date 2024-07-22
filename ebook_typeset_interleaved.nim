import std / [strutils]
from std / os import expandFilename
import flatBuffers

import std / [sequtils, strutils, xmltree, strtabs]
import ebook_utils

const HtmlHeader = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$#</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        .paragraph {
            margin-bottom: 30px;
            position: relative;
        }
        .original {
            margin-bottom: 5px;
        }
        .translation {
            font-size: 0.9em;
            color: #666;
            margin-bottom: 15px;
        }
        .indented {
            text-indent: 4em;  /* This will indent the first line */
            /* Or you can use this to indent the whole paragraph: */
            /* padding-left: 2em; */
        }
    </style>
</head>
"""

proc addParagraph(html: XmlNode, oP, tP: string, toIndent: bool) =
  # add HTML for last paragraph
  var x = newElement("div")
  x.attrs = {"class" : "paragraph"}.toXmlAttributes
  var p = newElement("p") # original
  let sf = if toIndent: " indented" else: ""
  p.attrs = {"class" : "original" & sf}.toXmlAttributes
  var t = newElement("p") # translation
  t.attrs = {"class" : "translation" & sf}.toXmlAttributes
  p.add newText(oP)
  t.add newText(tP)
  x.add p
  x.add t
  html.add x

proc fixupAndSplit(s: string): seq[string] =
  result = s.multiReplace(
    ("Mr. ", "Mr "),
    ("Mrs. ", "Mrs "),
    ("...", "…"),
  ).split(". ")

proc addParagraph(html: XmlNode, oP, tP: Paragraph, sentencesPerParagraph: int) =
  ## Adds the paragraps to the HTML node, and splits them after `sentencesPerParagraph`
  ## if > 0.
  if sentencesPerParagraph > 0:
    let oS = oP.s.fixupAndSplit()
    let numO = oS.len
    let tS = tP.s.fixupAndSplit()
    let numT = tS.len
    let markDirty = numO != numT
    let numP = if numO mod sentencesPerParagraph == 0: numO div sentencesPerParagraph
               else: (numO div sentencesPerParagraph) + 1
    for i in 0 ..< numP:
      let mIdxO = min((i + 1) * sentencesPerParagraph, numO)
      let mIdxT = min((i + 1) * sentencesPerParagraph, numT)
      let k = i * sentencesPerParagraph
      var o = oS[k ..< mIdxO].join(". ")
      var t: string
      if not markDirty:
        t = tS[k ..< mIdxT].join(". ")
      elif numT > numO:
        doAssert k < mIdxT, "k is somehow larger than end, despite numT > numO: " & $numT & ", " & $numT & ", k: " & $k
        if i < numP - 1: # all good
          t = tS[k ..< mIdxT].join(". ")
        else: # last iteration, take remainder of data
          t = tS[k ..< numT].join(". ")
      elif numT < numO:
        if k > mIdxT: # no more data!
          t = ""
        else: # all good
          t = tS[k ..< mIdxT].join(". ")
      if i > 0 and markDirty:
        t = "*" & t
      if i < numP - 1:
        o &= "."
        t &= "."
      html.addParagraph(o, t, toIndent = i > 0) # don't indent first iter
  else:
    html.addParagraph(oP.s, tP.s, false)

proc main(loadFrom, asText: string,
          paragraphDetect: string, # e.g. "    ",
          pageFooter: string, # e.g. "www.somewebsite.foo - Page",
          lastPage: int, # e.g. 529
          chapterDetect = "                                         ",
          title = "",
          outfile = "/tmp/test.html",
          sentencesPerParagraph = -1, ## If given > 0, split each paragraph after this many sentences
         ) =
  let orig  = parseBook(readFile(expandFilename asText),
                        paragraphDetect,
                        pageFooter,
                        chapterDetect,
                        lastPage
  )
  let trans = loadBuffer[RawBook](loadFrom)

  var chapter = 0
  var idx = 0
  var stop = 0 # end of page
  var lP = 0 # last paragraph started at this `idx`

  var html = newElement("body")

  for i, ch in trans.chapters:
    # <h1>Language Learning Example: Spanish to English</h1>
    var c = newElement("h2")
    c.add newText($ch.name)
    html.add c

    # preface
    for j in 0 ..< ch.preface.len:
      html.addParagraph(orig.chapters[i].preface[j], ch.preface[j], sentencesPerParagraph)
    # chapter body
    for j in 0 ..< ch.paragraphs.len:
      html.addParagraph(orig.chapters[i].paragraphs[j], ch.paragraphs[j], sentencesPerParagraph)

  writeFile(outfile, (HtmlHeader % title) & $html)

when isMainModule:
  import cligen
  dispatch main
