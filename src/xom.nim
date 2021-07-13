when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

import dom, macros, macroutils, strformat, strtabs, strutils, tables, xmltree


type Xom = ref object
  ## An object holding context for a conversion between `XmlNode` and
  ## `NimNode`.
  tree: XmlNode ## The XML represented by the object.
  id: CountTable[char] ## Keep track of how many elements of each type were already generated.
  buffer: string ## Buffer used during aglutination of text nodes.


func initXom*(x: XmlNode): Xom {.compileTime.} =
  ## Initialize a `Xom` object with a `XmlNode`.
  Xom(tree: x)


func adjustText(s: string): string {.compileTime.} =
  ## Remove whitespace from `s` as much as possible, hopefully not breaking
  ## any HTML rule. Basically, contigous whitespace is transformed into
  ## single `' '` characters.
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


func flushBufferTo(stmts, n: NimNode, q: Xom) {.compileTime.} =
  ## Flush the buffer of a `Xom` object by adding code to `result` to produce
  ## a text node attached to `n` with the buffer contents. Do nothing if the
  ## buffer is empty.
  if len(q.buffer) > 0:
    stmts.add superQuote do:
      `n`.appendChild(document.createTextNode(`adjustText(q.buffer)`))
    q.buffer = ""
    assert len(q.buffer) == 0


func createIdentFor(x: XmlNode, q: Xom): auto {.compileTime.} =
  ## Create a cute unique identifier for an XML node in the form
  ## `"<char><id>"`, where "`<char>`" is the first letter of the tag name and
  ## "`<id>`" is a an increasing number starting at zero.
  let c = x.tag[0]
  result = ident(&"{c}{q.id[c]}")
  q.id.inc(c)


func toNimNodeImpl(x: XmlNode, q: Xom): NimNode {.compileTime.} =
  ## Create a `NimNode` that constructs an HTML element with the same
  ## structure as `x` by using DOM calls, and use the context of the `Xom`
  ## object `q`. HTML comments are ignored and, if the whole tree is ignored,
  ## a `NimNode` representing `nil` is returned.
  if x.kind == xnElement:
    result = superQuote do:
      document.createElement(`x.tag`)

    if len(x) > 0 or attrsLen(x) > 0: # or forceEntry(x):
      let n = createIdentFor(x, q)

      result = newStmtList quote do:
        let `n` = `result`

      if not isNil(x.attrs):
        for key, value in x.attrs:
          result.add quote do:
            `n`.setAttribute(`key`, `value`)

      for xchild in x:
        if xchild.kind == xnText:
          q.buffer &= xchild.text
        else:
          flushBufferTo(result, n, q)
          let nchild = toNimNodeImpl(xchild, q)
          if nchild.kind != nnkNilLit:
            result.add quote do:
              `n`.appendChild(`nchild`)

      flushBufferTo(result, n, q)
      # entryCallback(x, n)
      result.add n
  elif x.kind == xnText:
    result = superQuote do:
      document.createTextNode(`adjustText(x.text)`)
  elif x.kind == xnComment:
    discard
  else:
    raise newException(ValueError, &"unsupported XML node type: '{x.kind}'")


converter toNimNode*(x: Xom): NimNode {.compileTime.} =
  ## Convert a `Xom` object to a `NimNode`. This converter constructs an HTML
  ## element with the same structure as `x` by using DOM calls. HTML comments
  ## are ignored and, if the whole tree is ignored, a `NimNode` representing
  ## `nil` is returned.
  toNimNodeImpl(x.tree, x)
