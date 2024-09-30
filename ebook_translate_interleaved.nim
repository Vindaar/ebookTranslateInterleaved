import std / [strutils]
import ebook_utils

import ollama
import flatBuffers

## To convert a PDF to a suitable `.txt`
## `pdftotext -layout the_ebook.pdf`
## -> produces a `.txt` with layout information (paragraph indents etc)

type
  Ollama = object
    ol: OllamaClient
    msg: string

proc initOllamaClient(msg: string): Ollama = Ollama(ol: newOllamaClient(), msg: msg)

import std / json
proc translate(ol: Ollama, s: string): string =
  let response = generateCompletion(ol.ol, "llama3", ol.msg & "\n\n" & s)
  result = response["response"].getStr
  echo "==============================\n"
  echo "Translating::: ", s
  echo "------------------------------\n"
  echo "Got: ", result
  echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n"
  echo "\n"

proc txt(fname: string,
          outfile: string, # outfile for the binary data file and partial files
          translateSetup: string, # file that contains the translation setup
          paragraphDetect: string, # e.g. "    ",
          pageFooter: string, # e.g. "www.somewebsite.foo - Page",
          lastPage: int, # e.g. 529
          chapterDetect = "                                         ",
          title = "",
         ) =
  ## `translateSetup` needs to be a file that contains the LLM prompt. See the example
  ## file in the repo, `example_translate_setup.txt`
  let b = parseBookTxt(readFile(fname), paragraphDetect, pageFooter, chapterDetect, lastPage = lastPage)

  var ollama = initOllamaClient(readFile(translateSetup))
  var page: string

  var outBook = TranslatedBook(RawBook())
  for i, ch in b.chapters:
    # 1. first the preface
    var oCh: Chapter
    oCh.name = ch.name
    for p in ch.preface:
      let ts = ollama.translate(p.s)
      oCh.preface.add Paragraph(startedPage: p.startedPage, s: ts)
    for j, p in ch.paragraphs:
      echo  "Paragraph!>>>> ", j, " in chapter: ", i
      let ts = ollama.translate(p.s)
      oCh.paragraphs.add Paragraph(startedPage: p.startedPage, s: ts)
    outBook.chapters.add oCh

    # Save current state after every page:
    outBook.saveBuffer(outfile.replace(".dat", "_partial.dat"))

  outBook.saveBuffer(outfile)

import std / [htmlparser, xmltree, strtabs]
proc epub(glob: string,
          outfile: string, # outfile for the binary data file and partial files
          translateSetup: string, # file that contains the translation setup
          divClassTranslate: string, # e.g. "bs3",
          tagsTranslate: string = "span"
         ) =
  ## `translateSetup` needs to be a file that contains the LLM prompt. See the example
  ## file in the repo, `example_translate_setup.txt`
  #let b = parseBook(readFile(fname), paragraphDetect, pageFooter, chapterDetect, lastPage = lastPage)

  #var ollama = initOllamaClient(readFile(translateSetup))

  ## XXX: fIX THIS!

  for html in epubFiles(glob):
    for parent in findAll(html, "div"):
      if "class" in parent.attrs and parent.attrs["class"] == divClassTranslate:
        # translate body
        var i = 0
        while i < parent.len:
          let ch = parent[i]
          if ch.kind == xnElement and ch.tag == tagsTranslate:
            var el = newElement("span")
            let att = {"class" : "translated"}.toXmlAttributes
            el.attrs = att
            el.add newText("FOOBAR")
            #echo "Inserting at ::: ", i
            echo "Into P : ", parent.kind, " and ", parent.attrs
            parent.insert(el, i + 1)
            inc i
          inc i

    writeFile("/tmp/test.html", $html)
    if true: quit()

  #var page: string
  #
  #var outBook = TranslatedBook(RawBook())
  #for i, ch in b.chapters:
  #  # 1. first the preface
  #  var oCh: Chapter
  #  oCh.name = ch.name
  #  for p in ch.preface:
  #    let ts = ollama.translate(p.s)
  #    oCh.preface.add Paragraph(startedPage: p.startedPage, s: ts)
  #  for j, p in ch.paragraphs:
  #    echo  "Paragraph!>>>> ", j, " in chapter: ", i
  #    let ts = ollama.translate(p.s)
  #    oCh.paragraphs.add Paragraph(startedPage: p.startedPage, s: ts)
  #  outBook.chapters.add oCh
  #
  #  # Save current state after every page:
  #  outBook.saveBuffer(outfile.replace(".dat", "_partial.dat"))
  #
  #outBook.saveBuffer(outfile)


when isMainModule:
  import cligen
  dispatchMulti([txt], [epub])
