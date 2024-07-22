import std/[strutils, sequtils, tables, options, algorithm, json, strformat, terminal]
from std / os import walkFiles, extractFilename, `/`, createDir, existsFile
import texParser, openai

proc walkDocument(elements: seq[TexNode], ignoredEnvs: seq[string], ignoredCmds: seq[string]): seq[TexNode] =
  for element in elements:
    case element.kind
    of txCommand:
      if element.name notin ignoredCmds:
        let arg = walkDocument(@[element.arguments], ignoredEnvs, ignoredCmds)
        doAssert arg.len == 1
        let opt = walkDocument(@[element.optionalArguments], ignoredEnvs, ignoredCmds)
        doAssert opt.len == 1
        result.add TexNode(kind: txCommand, name: element.name, arguments: arg[0], optionalArguments: opt[0])
    of txText: result.add(element)
    of txEnvironment:
      if element.envName notin ignoredEnvs:
        result.add TexNode(kind: txEnvironment, envName: element.envName, content: walkDocument(element.content, ignoredEnvs, ignoredCmds))
    of txArgList:
      let args = walkDocument(element.args, ignoredEnvs, ignoredCmds)
      result.add TexNode(kind: txArgList, args: args)
    of txOptList:
      let opts = walkDocument(element.opts, ignoredEnvs, ignoredCmds)
      result.add TexNode(kind: txOptList, opts: opts)
    of txArgument:
      let arg = walkDocument(element.arg, ignoredEnvs, ignoredCmds)
      result.add TexNode(kind: txArgument, arg: arg)
    of txOption:
      let opt = walkDocument(element.opt, ignoredEnvs, ignoredCmds)
      result.add TexNode(kind: txOption, opt: opt)
    else:
      echo "ELSE::: ", element.kind
      result.add element

## NOTE: The prompt was generated using Claude's prompt generator, but I ended
## up using gpt-4o-mini, because it is so much cheaper and gets the job done mostly.
## (Still needs manual work to make sure it's fine anyway!).
const sysPrompt = """
You are tasked with translating a section of a PhD thesis from Spanish to English. The translation should maintain academic writing style while staying close to the original Spanish version in terms of style. It is crucial that you do not alter any math expressions or TeX commands in any way.
"""
const tmpl = """
First, I will provide you with the context of the chapter in Spanish:

<spanish_context>
$#
</spanish_context>

Now, here is the specific section that needs to be translated:

<section_to_translate>
$#
</section_to_translate>

Please follow these guidelines for the translation:

1. Maintain an academic writing style appropriate for a PhD thesis.
2. Keep the translation close to the original Spanish version in terms of style and structure, but ensure it reads naturally in English. This means you can split sentences or slightly restructure text if required.
3. Do not translate or alter any section labels, figure labels, or references.
4. Preserve all math expressions and TeX commands exactly as they appear in the original text. Do not attempt to translate or modify these in any way.
5. If you encounter any technical terms or jargon that you're unsure about, translate them literally and include the original Spanish term in parentheses next to your translation.

Before providing your final translation, use the <scratchpad> tags to work through any challenging phrases or sentences. This will help you refine your translation before presenting the final version.

Present your final translation within <translation> tags. If you have any notes or comments about specific translation choices, include them after the translation within <translator_notes> tags.
"""


proc translateFile(client: OpenAIClient, fname: string, outpath: string, force: bool) =
  let latex = readFile(fname)
  let parsed = parseTex(latex)

  echo "Sections of file: ", fname
  var idx = 0
  for s in sections(parsed):
    let baseName = fname.extractFilename.replace(".tex", &"_translated_{idx}")
    let outfile = outpath / baseName

    # If an outfile for `outfile.json` exists, skip the translation
    if not force and existsFile(outfile & ".json"):
      stdout.styledWriteLine(fgGreen, "Skipping existing file: " & outfile)
      inc idx
      continue

    echo "SECTION::: \n\n"
    # 1) full file 2) section
    let prompt = tmpl % [latex, s]
    stdout.styledWriteLine(fgRed, "Prompt (without chapter):\n")
    stdout.styledWriteLine(fgYellow, tmpl % ["<FULL CHAPTER>", s])
    let response = client.completion(sysPrompt, prompt)
    stdout.styledWrite(fgRed, "Response: -----------------------------------------")
    stdout.styledWrite(fgGreen, response.pretty())

    writeFile(outfile & ".json", response.pretty())

    # convert to typed data
    let resOb = to(response, OpenAIResponse)
    let data = resOb.choices[0].message.content
    writeFile(outfile & ".tex", data)
    inc idx

proc main(fname = "",
          dir = "",
          outpath = "output",
          force = false,
          authinfo = "/home/foobar/.authinfo.gpg") =
  ## Force implies we overwrite and retranslate existing files
  # Usage example:
  let decryptedContent = decryptFile(authinfo)
  let apiKey = extractAPIKey(decryptedContent)
  echo "API Key: ", apiKey
  # Usage example:
  let client = newOpenAIClient(apiKey, "MainAPIKey")

  # create output path if not exists
  createDir(outpath)

  ## testing. Just start with one for now...
  if fname.len > 0:
    translateFile(client, fname, outpath, force)
  else:
    for f in walkFiles(dir):
      translateFile(client, f, outpath, force)


when isMainModule:
  import cligen
  dispatch main
