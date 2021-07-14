when not defined(js) and not defined(Nimdoc):
  {.error: "This module only works on the JavaScript platform".}

import dom, macros, macroutils, strformat, strtabs, strutils, sugar,
    tables, xmltree


type Xom = ref object
  ## An object holding context for a conversion between `XmlNode` and
  ## `NimNode`. It accepts some callbacks, which serve as transformers: a
  ## `bool` returned by them specifies whether code should be generated, and
  ## the given object can be modified prior to this generation.
  tree: XmlNode ## The XML represented by the object.
  id: CountTable[char] ## Keep track of how many elements of each type were already generated.
  buffer: string ## Buffer used during aglutination of text nodes.
  onCreateElement*: XmlNode -> bool
    ## Callback called when code with `createElement` is generated.
  onSetAttribute*: XmlNode -> bool
    ## Callback called when code with `setAttribute` is generated. If `false`
    ## is returned, all attributes are ignored.
  onCreateTextNode*: XmlNode -> bool
    ## Callback called when code with `createTextNode` is generated.


# forceEntry(x)
func defaultCallback(_: XmlNode): bool =
  ## Default behavior of all callbacks.
  true


func initXom*(x: XmlNode): Xom {.compileTime.} =
  ## Initialize a `Xom` object with a `XmlNode`.
  result = Xom(tree: x)
  result.onCreateElement = defaultCallback
  result.onSetAttribute = defaultCallback
  result.onCreateTextNode = defaultCallback


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


proc toNimNodeImpl(x: XmlNode, q: Xom): NimNode {.compileTime.} =
  ## Create a `NimNode` that constructs an HTML element with the same
  ## structure as `x` by using DOM calls, and use the context of the `Xom`
  ## object `q`. HTML comments are ignored and, if the whole tree is ignored,
  ## a `NimNode` representing `nil` is returned.
  case x.kind:
  of xnElement:
    if q.onCreateElement(x):
      result = superQuote do:
        document.createElement(`x.tag`)

      if len(x) > 0 or attrsLen(x) > 0:
        let n = createIdentFor(x, q)

        result = newStmtList quote do:
          let `n` = `result`

        if q.onSetAttribute(x) and not isNil(x.attrs):
          for key, value in x.attrs:
            result.add quote do:
              `n`.setAttribute(`key`, `value`)

        for xchild in x:
          if xchild.kind == xnText and q.onCreateTextNode(xchild):
            q.buffer &= xchild.text
          else:
            flushBufferTo(result, n, q)
            let nchild = toNimNodeImpl(xchild, q)
            if nchild.kind != nnkNilLit:
              result.add quote do:
                `n`.appendChild(`nchild`)

        flushBufferTo(result, n, q)
        result.add n
  of xnText:
    if q.onCreateTextNode(x):
      result = superQuote do:
        document.createTextNode(`adjustText(x.text)`)
  of xnComment:
    discard
  else:
    raise newException(ValueError, &"unsupported XML node type: '{x.kind}'")


converter toNimNode*(x: Xom): NimNode {.compileTime.} =
  ## Convert a `Xom` object to a `NimNode`. This converter constructs an HTML
  ## element with the same structure as `x` by using DOM calls. HTML comments
  ## are ignored and, if the whole tree is ignored, a `NimNode` representing
  ## `nil` is returned.
  toNimNodeImpl(x.tree, x)
