import std / [strutils]
import ebook_utils

import ollama, openai
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

import std / [htmlparser, xmltree, strtabs, terminal, os, times]

type
  Context = object
    oai: OpenAIClient # client
    sysPrompt: string
    fifo: FIFO ## The context as a FIFO
    parent: XmlNode # the current parent node for context to pass to translator
    retries = 10

  FIFO = object
    len: int
    data: seq[string]

proc initFifo(len: int): Fifo =
  Fifo(len: len,
       data: newSeqOfCap[string](len))

proc push(f: var Fifo, x: string) =
  if f.data.len < f.len:
    f.data.add x
  else: # kick out `0`, append to end
    f.data.delete(0)
    assert f.data.len < f.len
    f.push x

proc serialize(f: Fifo): string =
  result = f.data.join(" ")

const SysPrompt = """
You are tasked with translating a section of a novel from Spanish to English. The translation should stay close to the original Spanish version in terms of style. *Only* output the translation and *nothing else*.
"""
const Tmpl = """
First, I will provide you with the context of the chapter in Spanish:

<spanish_context>
$#
</spanish_context>

Now, here is the specific section that needs to be translated:

<section_to_translate>
$#
</section_to_translate>

Please follow these guidelines for the translation:

1. Only output the translation and nothing else.
2. Keep the translation close to the original Spanish version in terms of style and structure, but ensure it reads naturally in English.
3. It is better to have a translation that sounds stiff in English, if it helps making the relationship between the Spanish and English texts more apparent. Remember, this is intended as a language learning tool.
4. If you encounter terms that you're unsure about, keep the word without an attempt at a translation.
"""
#Before providing your final translation, use the <scratchpad> tags to work through any challenging phrases or sentences. This will help you refine your translation before presenting the final version.

#Present your final translation within <translation> tags. If you have any notes or comments about specific translation choices, include them after the translation within <translator_notes> tags.

proc requestImpl(ctx: Context, prompt: string, delay, retry: var int): JsonNode =
  try:
    result = ctx.oai.completion(ctx.sysPrompt, prompt)
  except ValueError:
    if retry < ctx.retries:
      delay *= 2
      sleep(delay)
      inc retry
      result = ctx.requestImpl(prompt, delay, retry)
    else:
      raise newException(ValueError, "Too many requests failed.")

proc translate(ctx: Context, txt: string): string =
  let prompt = Tmpl % [ctx.fifo.serialize, txt]
  echo "Prompt: ", prompt

  var retry = 0
  var delay = 1000
  let response = ctx.requestImpl(prompt, delay, retry)

  stdout.styledWrite(fgRed, "Response: -----------------------------------------")
  stdout.styledWrite(fgGreen, response.pretty())

  # convert to typed data
  let resOb = to(response, OpenAIResponse)
  result = resOb.choices[0].message.content

proc addParagraph(oP, tP: string, outer, inner: string, toIndent: bool): XmlNode =
  # add HTML for last paragraph
  var x = newElement(outer)
  x.attrs = {"class" : "paragraph"}.toXmlAttributes
  var p = newElement(inner) # original
  let sf = if toIndent: " indented" else: ""
  p.attrs = {"class" : "original" & sf}.toXmlAttributes
  var t = newElement(inner) # translation
  t.attrs = {"class" : "translation" & sf}.toXmlAttributes
  p.add newText(oP)
  t.add newText(tP)
  x.add p
  x.add t
  result = x

proc textIfAny(xml: XmlNode): string =
  ## Walks the node and returns any text contained.
  case xml.kind
  of xnText: result = xml.text
  else:
    for ch in xml:
      result.add textIfAny(ch)

proc translateIfAny(ctx: var Context, xml: XmlNode): (string, string) =
  ## Extracts any given text from the `xml` node and translates it.
  let txt = textIfAny(xml)
  if txt.len > 0:     # translate the text
    ctx.fifo.push txt
    let t = ctx.translate(txt)
    result = (txt, t)

proc translateNode(ctx: var Context, xml: XmlNode, divClassTranslate, tagsConsume, tagsReplace: string): XmlNode =
  case xml.kind
  of xnElement: # maybe contains to translate
    if xml.tag == tagsConsume: # e.g. `<span>` which we want to incorporate into the translation
      let (o, t) = ctx.translateIfAny(xml)
      result = addParagraph(o, t, "div", "p", false) # we also use `p`, otherwise the spans flow into each other
    elif xml.tag == tagsReplace: # e.g. `<p>` which we want to replace by `div`
      let (o, t) = ctx.translateIfAny(xml)
      result = addParagraph(o, t, "div", "p", true)
    else:
      echo "[INFO] Num children: ", xml.len
      result = newElement(xml.tag)
      result.attrs = xml.attrs
      for ch in xml:
        result.add ctx.translateNode(ch, divClassTranslate, tagsConsume, tagsReplace)
  of xnText: # translate
    echo "[INFO] Text node: " & $xml
    result = xml
  else:
    echo "[WARNING] Ignoring element: " & $xml.kind
    result = xml

proc epub(glob: string,
          outfile: string, # outfile for the binary data file and partial files
          translateSetup: string, # file that contains the translation setup
          divClassTranslate: string, # e.g. "bs3",
          tagsConsume: string = "span",
          tagsReplace: string = "p",
          fifoLength: int = 10,
          authinfo = "/home/basti/.authinfo.gpg") =
  ## `translateSetup` needs to be a file that contains the LLM prompt. See the example
  ## file in the repo, `example_translate_setup.txt`

  ## Force implies we overwrite and retranslate existing files
  # Usage example:
  let decryptedContent = decryptFile(authinfo)
  let apiKey = extractAPIKey(decryptedContent)
  echo "API Key: ", apiKey
  # Usage example:
  let client = newOpenAIClient(apiKey, "MainAPIKey")

  var ctx = Context(oai: client, sysPrompt: SysPrompt,
                    fifo: initFifo(fifoLength))

  for (file, html) in epubFiles(glob):
    let outfile = file.replace(".xhtml", "_translated.xhtml")
    if not fileExists(outfile):
      let t0 = epochTime()
      let x = ctx.translateNode(html, divClassTranslate, tagsConsume, tagsReplace)
      writeFile(outfile, $x)
      echo "[INFO] Translating file: ", file, " took ", (epochTime() - t0) / 60.0, " min"
    else:
      echo "[INFO] Skipping file: ", file, ", because it was already translated."

when isMainModule:
  import cligen
  dispatchMulti([txt], [epub])
