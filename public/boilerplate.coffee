{parseXY} = Simulator


class Boilerplate
  @colors =
    bridge: 'hsl(203, 67%, 51%)'
    negative: 'hsl(16, 68%, 50%)'
    nothing: 'hsl(0, 0%, 100%)'
    positive: 'hsl(120, 52%, 58%)'
    shuttle: 'hsl(283, 65%, 45%)'
    solid: 'hsl(184, 49%, 7%)'
    thinshuttle: 'hsl(283, 89%, 75%)'
    thinsolid: 'hsl(0, 0%, 71%)'

  @darkColors =
    bridge: "hsl(203,34%,43%)"
    negative: "hsl(16,40%,36%)"
    nothing: "hsl(0, 0%, 49%)"
    positive: "hsl(120,30%,43%)"
    shuttle: "hsl(287,24%,33%)"
    solid: "hsl(249,3%,45%)"
    thinshuttle: "hsl(283,31%,49%)"
    thinsolid: "hsl(0, 0%, 49%)"
  
  line = (x0, y0, x1, y1, f) ->
    dx = Math.abs x1-x0
    dy = Math.abs y1-y0
    ix = if x0 < x1 then 1 else -1
    iy = if y0 < y1 then 1 else -1
    e = 0
    for i in [0..dx+dy]
      f x0, y0
      e1 = e + dy
      e2 = e - dx
      if Math.abs(e1) < Math.abs(e2)
        x0 += ix
        e = e1
      else
        y0 += iy
        e = e2
    return

  enclosingRect = (a, b) ->
    tx: Math.min a.tx, b.tx
    ty: Math.min a.ty, b.ty
    tw: Math.abs(b.tx-a.tx) + 1
    th: Math.abs(b.ty-a.ty) + 1

  clamp = (x, min, max) -> Math.max(Math.min(x, max), min)

  # If you have a whole page of boilerplate instances, they should share the
  # same tool selection.
  @activeTool = 'nothing'

  @changeTool = (newTool) ->
    @activeTool = if newTool is 'solid' then null else newTool
    @onToolChanged? @activeTool

  @addKeyListener = (el) ->
    el.addEventListener 'keydown', (e) =>
      kc = e.keyCode

      newTool = ({
        # 1-8
        49: 'nothing'
        50: 'solid'
        51: 'positive'
        52: 'negative'
        53: 'shuttle'
        54: 'thinshuttle'
        55: 'thinsolid'
        56: 'bridge'

        80: 'positive' # p
        78: 'negative' # n
        83: 'shuttle' # s
        65: 'thinshuttle' # a
        69: 'nothing' # e
        71: 'thinsolid' # g
        68: 'solid' # d
        66: 'bridge' # b
      })[kc]
      @changeTool newTool if newTool

      document.activeElement?.boilerplate?.draw()

  
  CELL_SIZE = 20


  # ----- Utility methods for panning around the screen

  # given pixel x,y returns tile x,y
  screenToWorld: (px, py) ->
    return {tx:null, ty:null} unless px?
    # first, the top-left pixel of the screen is at |_ scroll * size _| px from origin
    px += Math.floor(@scroll_x * @size)
    py += Math.floor(@scroll_y * @size)
    # now we can simply divide and floor to find the tile
    tx = Math.floor(px / @size)
    ty = Math.floor(py / @size)
    {tx,ty}

  # given tile x,y returns the pixel x,y,w,h at which the tile resides on the screen.
  worldToScreen: (tx, ty) ->
    return {px:null, py:null} unless tx?
    px: tx * @size - Math.floor(@scroll_x * @size)
    py: ty * @size - Math.floor(@scroll_y * @size)

  zoomBy: (diff) ->
    @zoomLevel += diff
    @zoomLevel = clamp @zoomLevel, 1/CELL_SIZE, 5
    @size = Math.floor CELL_SIZE * @zoomLevel



  constructor: (@el, options) ->
    @zoomLevel = 1
    @zoomBy 0

    if options instanceof Simulator
      options = {simulator:options}

    @simulator = options.simulator || new Simulator()

    # In tile coordinates
    @scroll_x = options.initialX || 0
    @scroll_y = options.initialY || 0

    @canScroll = options.canScroll ? true

    #@el = document.createElement 'div'
    #@el.className = 'boilerplate'
    @el.tabIndex = 0 if @el.tabIndex is -1 # allow keyboard events
    @canvas = @el.appendChild document.createElement 'canvas'
    @canvas.className = 'draw'
    @uiCanvas = @el.appendChild document.createElement 'canvas'
    @uiCanvas.className = 'ui'
    @uiCanvas.style.pointerEvents = 'none'

    @el.boilerplate = this

    @resizeTo el.offsetWidth, el.offsetHeight
    #@el.onresize = -> console.log 'yo'

    @mouse = {x:null,y:null, mode:null}
    #@placing = 'nothing'
    @imminent_select = false
    @selectedA = @selectedB = null
    @selectOffset = null
    @selection = null

    @draw()


    # ----- Event handlers

    @el.onkeydown = (e) =>
      kc = e.keyCode

      switch kc
        when 37 # left
          @scroll_x -= 1 if @canScroll
        when 39 # right
          @scroll_x += 1 if @canScroll
        when 38 # up
          @scroll_y -= 1 if @canScroll
        when 40 # down
          @scroll_y += 1 if @canScroll

        when 16 # shift
          @imminent_select = true
        when 27 # esc
          @selection = @selectOffset = null

        when 88 # x
          @flip 'x' if @selection
        when 89 # y
          @flip 'y' if @selection
        when 77 # m
          @mirror() if @selection

      @draw()

    @el.onkeyup = (e) =>
      if e.keyCode == 16 # shift
        @imminent_select = false
        @draw()

    @el.addEventListener 'blur', =>
      @mouse.mode = null
      @imminent_select = false

    @el.onmousemove = (e) =>
      @imminent_select = !!e.shiftKey
      # If the mouse is released / pressed while not in the box, handle that correctly

      @el.onmousedown e if e.button && !@mouse.mode

      @mouse.from = {tx: @mouse.tx, ty: @mouse.ty}
      @mouse.x = clamp e.offsetX, 0, @el.offsetWidth - 1
      @mouse.y = clamp e.offsetY, 0, @el.offsetHeight - 1
      {tx:@mouse.tx, ty:@mouse.ty} = @screenToWorld @mouse.x, @mouse.y
      switch @mouse.mode
        when 'paint' then @paint()
        when 'select' then @selectedB = @screenToWorld @mouse.x, @mouse.y
      @draw()

    @el.onmousedown = (e) =>
      if e.shiftKey
        @mouse.mode = 'select'
        @selection = @selectOffset = null
        @selectedA = @screenToWorld @mouse.x, @mouse.y
        @selectedB = @selectedA
      else if @selection
        @stamp()
      else
        @mouse.mode = 'paint'
        @mouse.from = {tx:@mouse.tx, ty:@mouse.ty}
        @paint()
      @draw()

    @el.onmouseup = =>
      if @mouse.mode is 'select'
        @selection = @copySubgrid enclosingRect @selectedA, @selectedB
        @selectOffset =
          tx:@selectedB.tx - Math.min @selectedA.tx, @selectedB.tx
          ty:@selectedB.ty - Math.min @selectedA.ty, @selectedB.ty

      @mouse.mode = null
      @imminent_select = false

    @el.onmouseout = (e) =>
      # Pretend the mouse just went up at the edge of the boilerplate instance then went away.
      @el.onmousemove e
      @mouse.x = @mouse.y = @mouse.from = @mouse.tx = @mouse.ty = null
      # ... But if we're drawing, stay in drawing mode.
      @mouse.mode = null# if @mouse.mode is 'select'

    @el.onmouseenter = (e) =>
      @el.onmousedown(e) if e.which

    @el.onmousewheel = (e) =>
      return unless @canScroll
      if e.shiftKey
        oldsize = @size
        @zoomBy e.wheelDeltaY / 800

        @scroll_x += @mouse.x / oldsize - @mouse.x / @size
        @scroll_y += @mouse.y / oldsize - @mouse.y / @size
      else
        @scroll_x += e.wheelDeltaX / (-2 * @size)
        @scroll_y += e.wheelDeltaY / (-2 * @size)
      e.preventDefault()
      @draw()

  resizeTo: (width, height) ->
    #@el.style.width = width + 'px'
    #@el.style.height = height + 'px'
    @uiCanvas.width = @canvas.width = width * devicePixelRatio
    @uiCanvas.height = @canvas.height = height * devicePixelRatio
    #@canvas.style.width = @uiCanvas.style.width = width + 'px'
    #@canvas.style.height = @uiCanvas.style.height = height + 'px'
    @ctx = @canvas.getContext '2d'
    @ctx.scale devicePixelRatio, devicePixelRatio

    @draw()

  paint: ->
    throw 'Invalid placing' if Boilerplate.activeTool is 'move'
    {tx, ty} = @mouse
    {tx:fromtx, ty:fromty} = @mouse.from
    fromtx ?= tx
    fromty ?= ty

    line fromtx, fromty, tx, ty, (x, y) =>
      @simulator.set x, y, Boilerplate.activeTool
      @onEdit? x, y, Boilerplate.activeTool

  #########################
  # SELECTION             #
  #########################
  copySubgrid: (rect) ->
    {tx, ty, tw, th} = rect
    subgrid = {tw,th}
    for y in [ty..ty+th]
      for x in [tx..tx+tw]
        if s = @simulator.grid[[x,y]]
          subgrid[[x-tx,y-ty]] = s
    subgrid

  flip: (dir) ->
    return unless @selection
    new_selection = {tw:tw = @selection.tw, th:th = @selection.th}
    for k,v of @selection
      {x:tx,y:ty} = parseXY k
      tx_ = if 'x' in dir then tw-1 - tx else tx
      ty_ = if 'y' in dir then th-1 - ty else ty
      new_selection[[tx_,ty_]] = v
    @selection = new_selection

  mirror: ->
    return unless @selection
    new_selection = {tw:tw = @selection.th, th:th = @selection.tw}
    for k,v of @selection
      {x:tx,y:ty} = parseXY k
      new_selection[[ty,tx]] = v
    @selection = new_selection

  stamp: ->
    throw new Error 'tried to stamp without a selection' unless @selection
    {tx:mtx, ty:mty} = @screenToWorld @mouse.x, @mouse.y
    mtx -= @selectOffset.tx
    mty -= @selectOffset.ty

    for y in [0...@selection.th]
      for x in [0...@selection.tw]
        tx = mtx+x
        ty = mty+y
        if (s = @selection[[x,y]]) != @simulator.get tx,ty
          @simulator.set tx, ty, s
          @onEdit? tx, ty, s

  copy: (e) ->
    #console.log 'copy'
    if @selection
      e.clipboardData.setData 'text', JSON.stringify @selection

      console.log JSON.stringify @selection
    e.preventDefault()

  paste: (e) ->
    console.log 'paste'
    data = e.clipboardData.getData 'text'
    if data
      try
        @selection = JSON.parse data
        @selectOffset = {tx:0, ty:0}


  #########################
  # DRAWING               #
  #########################

  draw: ->
    return if @needsDraw
    @needsDraw = true
    requestAnimationFrame =>
      @drawFrame()
      @needsDraw = false

  drawFrame: ->
    @ctx.fillStyle = Boilerplate.colors['solid']
    @ctx.fillRect 0, 0, @canvas.width, @canvas.height

    @drawGrid()

    @drawEditControls()

  drawGrid: ->
    # Draw the tiles
    pressure = @simulator.getPressure()
    for k,v of @simulator.grid
      {x:tx,y:ty} = parseXY k
      {px, py} = @worldToScreen tx, ty
      if px+@size >= 0 and px < @canvas.width and py+@size >= 0 and py < @canvas.height
        @ctx.fillStyle = Boilerplate.colors[v]
        @ctx.fillRect px, py, @size, @size

        if v is 'nothing' and (v2 = @simulator.get(tx,ty-1)) isnt 'nothing'
          @ctx.fillStyle = Boilerplate.darkColors[v2 ? 'solid']
          @ctx.fillRect px, py, @size, @size*0.3

        if (p = pressure[k]) and p != 0
          @ctx.fillStyle = if p < 0 then 'rgba(255,0,0,0.2)' else 'rgba(0,255,0,0.15)'
          @ctx.fillRect px, py, @size, @size

    zeroPos = @worldToScreen 0, 0
    @ctx.lineWidth = 3
    @ctx.strokeStyle = 'yellow'

  drawEditControls: ->
    mx = @mouse.x
    my = @mouse.y
    {tx:mtx, ty:mty} = @screenToWorld mx, my
    {px:mpx, py:mpy} = @worldToScreen mtx, mty

    if @mouse.mode is 'select'
      sa = @selectedA
      sb = @selectedB
    else if @imminent_select
      sa = sb = {tx:mtx, ty:mty}

    @ctx.lineWidth = 1

    # Draw the mouse hover state
    if @mouse.tx != null
      if sa
        {tx, ty, tw, th} = enclosingRect sa, sb
        {px, py} = @worldToScreen tx, ty
        @ctx.fillStyle = 'rgba(0,0,255,0.5)'
        @ctx.fillRect px, py, tw*@size, th*@size

        @ctx.strokeStyle = 'rgba(0,255,255,0.5)'
        @ctx.strokeRect px, py, tw*@size, th*@size
      else if @selection # mouse.tx is null when the mouse isn't in the div
        @ctx.globalAlpha = 0.8
        for y in [0...@selection.th]
          for x in [0...@selection.tw]
            {px, py} = @worldToScreen x+mtx-@selectOffset.tx, y+mty-@selectOffset.ty
            if px+@size >= 0 and px < @canvas.width and py+@size >= 0 and py < @canvas.height
              v = @selection[[x,y]]
              @ctx.fillStyle = if v then Boilerplate.colors[v] else Boilerplate.colors['solid']
              @ctx.fillRect px, py, @size, @size
        @ctx.strokeStyle = 'rgba(0,255,255,0.5)'
        @ctx.strokeRect mpx - @selectOffset.tx*@size, mpy - @selectOffset.ty*@size, @selection.tw*@size, @selection.th*@size
        @ctx.globalAlpha = 1
      else if mpx?
        # Mouse hover
        @ctx.fillStyle = Boilerplate.colors[Boilerplate.activeTool ? 'solid']
        @ctx.fillRect mpx + @size/4, mpy + @size/4, @size/2, @size/2

        @ctx.strokeStyle = if @simulator.get(mtx, mty) then 'black' else 'white'
        @ctx.strokeRect mpx + 1, mpy + 1, @size - 2, @size - 2


    return

