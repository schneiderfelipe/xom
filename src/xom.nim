import macros, macroutils, xmltree, dom

func createTree*(x: XmlNode): NimNode =
  if x.kind == xnElement:
    discard
  elif x.kind == xnText:
    result = superQuote do:
      document.createTextNode(`x.text`)
