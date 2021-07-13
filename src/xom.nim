import macros, macroutils, xmltree, dom

var id {.compileTime.} = 0

proc createIdentFor(x: XmlNode): NimNode =
  result = ident(x.tag[0] & $id)
  id += 1

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
