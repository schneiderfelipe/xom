import dom, htmlparser, macros, xom

macro html(s: string{lit}): Node =
  parseHtml(s.strVal).initXom()

document.body.appendChild html"<p>Hello!</p>"
