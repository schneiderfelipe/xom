import macros, macroutils, xmltree, dom, tables

var id {.compileTime.}: CountTable[char]

proc createIdentFor(x: XmlNode): NimNode =
  ## Create a cute unique identifier for the node in the form `"<char><id>"`,
  ## where "`<char>`" is the first letter of the tag name and "`<id>`" is a an
  ## increasing number starting at zero.
  let c = x.tag[0]
  result = ident(c & $id[c])
  id.inc(c)

proc createTree*(x: XmlNode): NimNode =
  if x.kind == xnElement:
    result = superQuote do:
      document.createElement(`x.tag`)
    if len(x) > 0 or attrsLen(x) > 0:  # or forceEntry(x):
      let n = createIdentFor(x)
      result = newStmtList superQuote do:
        let `n` = `result`

      for child in x:
        result.add superQuote do:
          `n`.appendChild(`createTree(child)`)

      result.add n
  elif x.kind == xnText:
    result = superQuote do:
      document.createTextNode(`x.text`)
  else:
    raise newException(ValueError, "unsupported XML node type: " & $x.kind)
