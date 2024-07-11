import std / [strutils]
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
    </style>
</head>
"""

proc addParagraph(html: XmlNode, oP, tP: string) =
  # add HTML for last paragraph
  var x = newElement("div")
  x.attrs = {"class" : "paragraph"}.toXmlAttributes
  var p = newElement("p") # original
  p.attrs = {"class" : "original"}.toXmlAttributes
  var t = newElement("p") # translation
  t.attrs = {"class" : "translation"}.toXmlAttributes
  p.add newText(oP)
  t.add newText(tP)
  x.add p
  x.add t
  html.add x

proc addParagraph(html: XmlNode, oP, tP: Paragraph, sentencesPerParagraph: int) =
  ## Adds the paragraps to the HTML node, and splits them after `sentencesPerParagraph`
  ## if > 0.
  if sentencesPerParagraph > 0:
    let oS = oP.s.split(". ")
    let numO = oS.len
    let tS = tP.s.split(". ")
    let numT = tS.len
    let markDirty = numO != numT
    let numP = numO div sentencesPerParagraph
    for i in 0 ..< numP:
      let mIdxO = min((i + 1) * sentencesPerParagraph, numO)
      let mIdxT = min((i + 1) * sentencesPerParagraph, numP)
      var o = oS[i ..< i + mIdxO].join(". ")
      var t = tS[i ..< i + mIdxT].join(". ")
      if i > 0:
        o = "\t" & o
        t = if markDirty: "*\t" & t else: "\t" & t
      html.addParagraph(o, t)
  else:
    html.addParagraph(oP.s, tP.s)

proc main(loadFrom, asText: string,
          paragraphDetect: string, # e.g. "    ",
          pageFooter: string, # e.g. "www.somewebsite.foo - Page",
          lastPage: int, # e.g. 529
          chapterDetect = "                                         ",
          title = "",
          outfile = "/tmp/test.html",
          sentencesPerParagraph = -1, ## If given > 0, split each paragraph after this many sentences
         ) =
  let orig  = parseBook(readFile(asText),
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
