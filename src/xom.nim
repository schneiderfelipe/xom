import dom, macros, macroutils, strtabs, strutils, tables, xmltree


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
    if len(x) > 0 or attrsLen(x) > 0: # or forceEntry(x):
      let n = createIdentFor(x)
      result = newStmtList superQuote do:
        let `n` = `result`

      if not isNil(x.attrs):
        for k, v in x.attrs:
          result.add superQuote do:
            `n`.setAttribute(`k`, `v`)

      for xc in x:
        let nc = createTree(xc)
        if nc.kind != nnkNilLit:
          result.add superQuote do:
            `n`.appendChild(`nc`)

      result.add n
  elif x.kind == xnText:
    var nt = x.text
    if nt.isEmptyOrWhitespace:
      nt = " "
    result = superQuote do:
      document.createTextNode(`nt`)
  elif x.kind == xnComment:
    discard
  else:
    raise newException(ValueError, "unsupported XML node type: '" & $x.kind & "'")
