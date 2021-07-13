import macros, macroutils, xmltree, dom

func createTree*(x: XmlNode): NimNode =
  if x.kind == xnElement:
    result = superQuote do:
      document.createElement(`x.tag`)
  elif x.kind == xnText:
    result = superQuote do:
      document.createTextNode(`x.text`)
  else:
    raise newException(ValueError, "unsupported XML node type: " & $x.kind)
