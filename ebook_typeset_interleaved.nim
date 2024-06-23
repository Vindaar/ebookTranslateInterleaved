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

proc addParagraph(html: XmlNode, oP, tP: Paragraph) =
  # add HTML for last paragraph
  var x = newElement("div")
  x.attrs = {"class" : "paragraph"}.toXmlAttributes
  var p = newElement("p") # original
  p.attrs = {"class" : "original"}.toXmlAttributes
  var t = newElement("p") # translation
  t.attrs = {"class" : "translation"}.toXmlAttributes
  p.add newText(oP.s)
  t.add newText(tP.s)
  x.add p
  x.add t
  html.add x

proc main(loadFrom, asText: string,
          paragraphDetect: string, # e.g. "    ",
          pageFooter: string, # e.g. "www.somewebsite.foo - Page",
          lastPage: int, # e.g. 529
          chapterDetect = "                                         ",
          title = "",
          outfile = "/tmp/test.html",
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
      html.addParagraph(orig.chapters[i].preface[j], ch.preface[j])
    # chapter body
    for j in 0 ..< ch.paragraphs.len:
      html.addParagraph(orig.chapters[i].paragraphs[j], ch.paragraphs[j])

  writeFile(outfile, (HtmlHeader % title) & $html)

when isMainModule:
  import cligen
  dispatch main
