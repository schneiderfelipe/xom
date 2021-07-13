when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

import dom, macros, macroutils, strformat, strtabs, strutils, tables, xmltree


var id {.compileTime.}: CountTable[char]
  ## Keep track of how many elements of each type were already generated.
var buffer {.compileTime.}: string
  ## Aglutinate text nodes before insertion.


proc createIdentFor(x: XmlNode): auto {.compileTime.} =
  ## Create a cute unique identifier for the node in the form `"<char><id>"`,
  ## where "`<char>`" is the first letter of the tag name and "`<id>`" is a an
  ## increasing number starting at zero.
  let c = x.tag[0]
  result = ident(&"{c}{id[c]}")
  id.inc(c)


func adjustText(s: string): string {.compileTime.} =
  ## Remove whitespace as much as possible, hopefully not breaking anything.
  ## Basically, contigous whitespace is transformed into single `' '`
  ## characters.
  let start = low(s)

  if len(s) > 0:
    if not s[start].isSpaceAscii:
      result &= s[start]
    else:
      result &= ' '

  for i in start+1..high(s):
    if not s[i].isSpaceAscii:
      result &= s[i]
    elif not s[i-1].isSpaceAscii:
      result &= ' '


proc flushBufferTo(stmts, n: NimNode) {.compileTime.} =
  ## Flush the buffer by adding code to `result` to produce a text node
  ## attached to `n` with the buffer contents.
  if len(buffer) > 0:
    stmts.add superQuote do:
      `n`.appendChild(document.createTextNode(`adjustText(buffer)`))
    buffer = ""
    assert len(buffer) == 0


proc createTree*(x: XmlNode): NimNode {.compileTime.} =
  ## Create a `NimNode` that constructs an HTML element with the same
  ## structure as `x` by using DOM calls. HTML comments are ignored and, if
  ## the whole tree is ignored, a `NimNode` representing `nil` is returned.
  if x.kind == xnElement:
    result = superQuote do:
      document.createElement(`x.tag`)

    if len(x) > 0 or attrsLen(x) > 0: # or forceEntry(x):
      let n = createIdentFor(x)

      result = newStmtList quote do:
        let `n` = `result`

      if not isNil(x.attrs):
        for key, value in x.attrs:
          result.add quote do:
            `n`.setAttribute(`key`, `value`)

      for xchild in x:
        if xchild.kind == xnText:
          buffer &= xchild.text
        else:
          flushBufferTo(result, n)
          let nchild = createTree(xchild)
          if nchild.kind != nnkNilLit:
            result.add quote do:
              `n`.appendChild(`nchild`)

      flushBufferTo(result, n)
      # entryCallback(x, n)
      result.add n
  elif x.kind == xnText:
    result = superQuote do:
      document.createTextNode(`adjustText(x.text)`)
  elif x.kind == xnComment:
    discard
  else:
    raise newException(ValueError, &"unsupported XML node type: '{x.kind}'")
