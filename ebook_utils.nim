import std / [strutils, parseutils, sequtils, os, htmlparser, xmltree, strtabs]

proc parsePage*(book: string, start: int, pageDetect: static string): (int, int, string) =
  ## Returns the next page from `start` using `pageDetect` as the page boundary &
  ## page number detector
  var buf: string
  var idx = book.parseUntil(buf, pageDetect, start)
  var page: int
  if start + pageDetect.len + idx < book.len:
    idx += book.parseInt(page, start + pageDetect.len + idx)

    result = (page, start + pageDetect.len + idx, buf)
  else:
    result = (-1, -1, "")

import std / sequtils
proc onlyNumber*(s: string): bool =
  if s.strip.len == 0: result = false
  else: result = s.strip.allIt(it.isDigit())

type
  Paragraph* = object
    startedPage*: bool ## Whether this paragraph started the page
    s*: string
  Chapter* = object
    name*: string # chapter number or name
    preface*: seq[Paragraph] # (Brandon Sanderson usually have a preface on each chapter)
    paragraphs*: seq[Paragraph] # all paragraphs in the chapter
  RawBook* = object
    chapters*: seq[Chapter]

  TranslatedBook* {.borrow: `.`.} = distinct RawBook

proc getPreface(ps: var seq[Paragraph]): seq[Paragraph] =
  if ps.len == 0: return # nothing to do!
  var frm = 0
  for i in countdown(ps.high, 0):
    if ps[i].startedPage:
      frm = i # copy from `i`
      break
  result = ps[frm .. ^1]
  doAssert frm - 2 > 0, "Index problem! : " & $frm & " in : " & $ps
  ps.setLen(frm - 2) # remove up to page begin

proc addIf(ps: var seq[Paragraph], p: Paragraph) =
  ## Adds it if non trivial
  if p.s.len > 0:
    ps.add p

proc parseBookTxt*(data: string,
                   paragraphDetect: string,
                   pageFooter: string,
                   chapterDetect: string,
                   lastPage: int): RawBook =
  ## Parses a raw book as a string into a `RawBook`.
  ## Splits into chapters and paragraphs, takes into account prefaces.
  ##
  ## Can contain page footers that start with a `pageFooter`.
  ##
  ## Input should be a txt version of a PDF, produced via:
  ##
  ## `pdftotext -layout foo.pdf`
  ## (`-layout` makes it keep the indentation!)
  ##
  ##
  ##       Kelsier contó hasta diez antes de buscar en su interior y quemar sus metales. Su
  ##   cuerpo se llenó de fuerza, claridad y poder. Sonrió. Luego, quemando cinc, extendió
  ##   su poder y se apoderó con firmeza de las emociones del inquisidor. La criatura se
  ##   detuvo en el acto, luego se dio la vuelta y miró hacia el edificio del Cantón.
  ##       Ahora vamos a jugar a perseguirnos, tú y yo, pensó Kelsier.
  ##
  ##
  ##
  ##
  ##                             www.lectulandia.com - Página 43
  ##          Llegamos a Terris a principios de semana y tengo que decir que el paisaje me pareció maravilloso.
  ##      Las grandes montañas al norte, con sus cimas nevadas y sus faldas boscosas, se alzan como dioses
  ##      guardianes sobre esta tierra de verde fertilidad. Mis propias tierras del sur son llanas: creo que serían
  ##      menos temibles si hubiera unas cuantas montañas para dar variedad al terreno.
  ##          Aquí la gente se dedica sobre todo al pastoreo, aunque no son extraños los leñadores y los granjeros.
  ##      Es una tierra de pastos, desde luego. Parece raro que un sitio tan agrícola sea la cuna de las profecías y
  ##      las ideas teológicas en las que se basa el mundo entero en la actualidad.
  ##
  ##
  ##                                                         3
  ##
  ##
  ##
  ##
  ##   C     amon contó sus monedas, dejando caer los cuartos de oro uno a uno en un
  ##         cofrecito que había en la mesa. Todavía parecía un poco aturdido, y bien podía
  ##   estarlo. Tres mil cuartos era una fabulosa cantidad de dinero, mucho más de lo que
  ##   Camon ganaba incluso en un año muy bueno. Sus amigotes más íntimos estaban
  ##   sentados a la mesa con él, mientras la cerveza y las risas fluían libremente.

  # 1. for every new chapter, all paragraphs from page begin are preface
  # 2. paragraph only if `paragraphDetect` *and* upper case
  # 3. First letter of chapter may be capitalized + have space, filter

  var ps = newSeq[Paragraph]()
  var p = Paragraph()
  var ch: Chapter

  var pageCount = 0

  template addChapter() {.dirty.} =
    # add last paragraph (likely from preface)
    ps.addIf p #
    let pf = getPreface(ps)
    ch.paragraphs = ps
    result.chapters.add ch


  for l in data.splitLines:
    echo "??? ", l
    if l.startsWith('\f'): inc pageCount
    if pageCount >= lastPage:
      addChapter()
      break

    if l.startsWith(chapterDetect):
      addChapter()
      # create new Chapter
      ch.name = l.strip
      ch.preface = pf
      ps.setLen(0) # empty
      p.s.setLen(0)
    elif l.strip.startsWith(pageFooter): continue # ignore footer
    elif l.startsWith(paragraphDetect) and (not l.strip[0].isLowerAscii): # if starts with lower ascii, probably second row of chapter
      # add paragraph
      ps.addIf p
      p.startedPage = false
      p.s.setLen(0)
      p.s.add l.strip
    elif l.startsWith('\f') and l.startsWith($'\f' & paragraphDetect): # new page + new paragraph
      ps.addIf p # add last paragraph
      p.s.setLen(0)
      p.startedPage = true
      p.s.add l.strip
    else:
      p.s.add " " & l.strip # add a space!

iterator getTexts*(html: XmlNode, divClassTranslate: string): XmlNode =
  for x in findAll(html, "div"):
    if "class" notin x.attrs or
       x.attrs["class"] != divClassTranslate:
      continue
    yield x

iterator epubFiles*(glob: string): (string, XmlNode) =
                    #divClassTranslate: string,
                    #tagsTranslate: string = "span"): XmlNode =
  ## Parses a raw book as a string into a `RawBook`.
  ## Splits into chapters and paragraphs, takes into account prefaces.
  ##
  ## The input book must be multiple HTML files extracted from an `epub` file.
  ## This approach has the advantage that we keep the text formatting compared
  ## to the txt based approach.
  ##
  ## `glob` is a file name glob that will be used to parse all HTML files matching it.
  ##
  ## `divClassTranslate` is the div class that contains data to be translated. Everything else
  ## will be left untouched.
  ## `tagsTranslate` are the tags that contain text to be translated in that div.
  ## This will usually be a `<span>`. Between span tags might be empty `<p>` tags.
  for f in walkFiles(glob.expandTilde()):
    let html = loadHtml(f)
    yield (f, html)

when isMainModule:

  when false: # text based
    let b = parseBook(readFile("/t/el-imperio-final.-ed.-revisada-brandon-sanderson-z-library.txt"),
                      "    ",
                      "www.lectulandia.com - Página",
                      "                                         ",
                      lastPage = 529
    )
    for ch in b.chapters:
      #echo "\t: ", ch.preface, "\n\n"
      echo "Chapter: ", ch.name, " has ", ch.paragraphs.len, " paragraphs"
      #for p in ch.paragraphs:
      #  echo "\t: ", p
      #  if p.s.len > 4000: quit()

  let b = parseBookEpub("~/org/Books/elPozoDeLaAscension/52_split*.xhtml", "bs3")
