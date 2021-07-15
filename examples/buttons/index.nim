import dom, xom
import htmlparser, macros, sugar, strformat, strtabs, strutils, xmltree


type Component = ref object
  r: Node
  c: void -> Node
  u: void -> void


proc create(self: Component) =
  self.r = self.c()


proc update(self: Component) =
  self.u()


func mount(target: Node, self: Component) =
  assert self.r != nil, "component not initialized"
  target.appendChild(self.r)


macro html(s: string{lit}): Component =
  let context = parseHtml(s.strVal).initXom()
  let defineSection, createSection, eventSection, updateSection = newStmtList()

  context.onEnter = func(node: XmlNode): Command =
    case node.kind:
    of xnElement:
      if not isNil(node.attrs):
        for key, value in node.attrs:
          if '{' in value or '}' in value:
            return EmitNamed
    of xnText:
      let text = node.text
      if '{' in text or '}' in text:
        return EmitNamed
    else:
      return Emit

  context.onEmitNamed = func(node: XmlNode, name: NimNode) =
    case node.kind:
    of xnElement:
      if not isNil(node.attrs):
        var attrs: seq[(string, string)]
        for key, value in node.attrs:
          if '{' notin value and '}' notin value:
            attrs.add (key, value)
          elif key.startsWith("on"):
            let
              key = key[2..^1]
              callback = ident(value[1..^2])
            eventSection.add quote do:
              `name`.addEventListener(`key`, proc(e: Event) =
                `callback`(e)
                u(),
              )
          else:
            updateSection.add quote do:
              `name`.setAttribute(`key`, &`value`)
        node.attrs = attrs.toXmlAttributes()
    of xnText:
      let text = node.text
      if '{' in text or '}' in text:
        node.text = ""
        updateSection.add quote do:
          `name`.textContent = &`text`
    else:
      discard

  let all: NimNode = context
  for stm in all:
    if stm.kind == nnkLetSection:
      defineSection.add stm
    else:
      createSection.add stm

  result = quote do:
    proc initComponent: Component =
      `defineSection`
      proc u =
        `updateSection`
      Component(
        c: proc: Node =
        result = `createSection`
        `eventSection`,
        u: u,
        # TODO: make a delete procedure that detaches event listeners and
        # unmounts?
      )
    initComponent()


when isMainModule:
  var count = 0

  proc increase(_: Event) =
    count += 1
    echo count
  proc decrease(_: Event) =
    count -= 1
    echo count

  var app = html"""
    <div id=app>
      <button onclick={increase}>+</button>
      <div>{count}</div>
      <button onclick={decrease}>-</button>
    </div>
  """
  app.create()
  app.update()
  document.body.mount(app)
