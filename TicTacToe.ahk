#NoEnv
SetBatchLines, -1

#Include gdip\Gdip_All.ahk
#Include lib\WinEvents.ahk


; Start gdi+
If !pToken := Gdip_Startup()
{
	MsgBox, 48, gdiplus error!, Gdiplus failed to start. Please ensure you have gdiplus on your system
	ExitApp
}

; Start the game
TicTacToe.__Delete := Func("ExitApp")
new TicTacToe()
return


ExitApp(this)
{
	ExitApp
}

class TicTacToe
{
	Width := 600
	Height := 600
	
	__New()
	{
		; Initialize internal objects
		this.Board := [["","",""],["","",""],["","",""]]
		this.Particles := []
		
		; Create the GUI
		Gui, +hWndhOldWnd
		Gui, New, +hWndhWnd +Resize
		Gui, Color, 303030
		Gui, Margin, 0, 0
		Gui, Add, Progress, % "w" this.Width " h" this.Height " hWndhProgress Background303030", 0
		this.hWnd := hWnd
		
		; Get the GDI+ objects
		this.hProgress := hProgress
		this.hProgressDC:= GetDC(this.hProgress)
		this.hDC := CreateCompatibleDC()
		this.hDIB := CreateDIBSection(this.Width, this.Height)
		SelectObject(this.hDC, this.hDIB)
		this.pGraphics := Gdip_GraphicsFromHDC(this.hDC)
		
		; Bind some event handling functions
		this.Bound := []
		this.Bound.ButtonDown := this.ButtonDown.Bind(this)
		this.Bound.Paint := this.Paint.Bind(this)
		this.Bound.Step := this.Step.Bind(this)
		
		; Register for events
		WinEvents.Register(this.hWnd, this)
		OnMessage(0x201, this.Bound.ButtonDown) ; WM_LBUTTONDOWN
		OnMessage(0x204, this.Bound.ButtonDown) ; WM_RBUTTONDOWN
		OnMessage(0xF,   this.Bound.Paint)      ; WM_PAINT
		
		; Show the GUI
		this.Redraw()
		Gui, Show,, Tic Tac Toe
		Gui, %hOldWnd%: Default
	}
	
	GuiSize(hWnd, EventInfo, Width, Height)
	{
		; Save the new size
		this.Width := Width
		this.Height := Height
		
		; Delete the original graphics buffer
		Gdip_DeleteGraphics(this.pGraphics)
		DeleteObject(this.hDIB)
		DeleteDC(this.hDC)
		
		; Create a new graphics buffer
		this.hDC := CreateCompatibleDC()
		this.hDIB := CreateDIBSection(Width, Height)
		SelectObject(this.hDC, this.hDIB)
		this.pGraphics := Gdip_GraphicsFromHDC(this.hDC)
		
		; Update the GUI
		this.Redraw()
		GuiControl, Move, % this.hProgress, w%Width% h%Height%
		this.Paint()
	}
	
	GuiClose()
	{
		; Stop particle generation
		BoundFunc := this.Bound.Step
		SetTimer, %BoundFunc%, Delete
		
		; Release WinEvents handler
		WinEvents.Unregister(this.hWnd)
		
		; Release WM hooks
		OnMessage(0x201, this.Bound.ButtonDown, 0) ; WM_LBUTTONDOWN
		OnMessage(0x204, this.Bound.ButtonDown, 0) ; WM_RBUTTONDOWN
		OnMessage(0xF,   this.Bound.Paint,      0) ; WM_PAINT
		
		; Break all the BoundFunc circular references
		this.Bound := ""
	}
	
	Paint(wParam:=0, lParam:=0, Msg:=0, hWnd:=0)
	{
		; Filter by hWnd when called from OnMessage
		if (hWnd != 0 && hWnd != this.hWnd)
			return
		
		Sleep, 0 ; Ensures redraw in edge cases (fast movement and restore from minimize)
		BitBlt(this.hProgressDC, 0, 0, this.Width, this.Height, this.hDC, 0, 0)
	}
	
	ButtonDown(wParam, lParam, Msg, hWnd)
	{
		; Filter by hWnd
		if (hWnd != this.hProgress)
			return
		
		; Don't respond if the game is over
		if this.HasWon
			return
		
		; Get the board square that was clicked
		x := (lParam&0xFFFF) // (this.Width // 3) + 1
		y := (lParam>>16) // (this.Height // 3) + 1
		
		; Update the square
		if !this.Board[y, x]
			this.Board[y, x] := (this.Player := !this.Player) ? "X" : "O"
		
		; Update the GUI
		this.Redraw()
		this.Paint()
		
		; Check if someone won
		if (Winner := this.CheckWin())
		{
			this.HasWon := True
			if (Winner == "Tie")
				MsgBox, You tied
			else
			{
				; Bring on the confetti!
				BoundFunc := this.Bound.Step
				SetTimer, %BoundFunc%, 0
			}
		}
	}
	
	Step()
	{
		this.SpawnParticle()
		
		; Update each particle, discarding those that fall off-screen
		NewParticles := []
		for i, Particle in this.Particles
		{
			Particle.Step()
			
			if (Particle.y <= this.Height)
				NewParticles.Push(Particle)
		}
		this.Particles := NewParticles
		
		; Update the GUI
		this.Redraw()
		this.Paint()
	}
	
	Redraw()
	{
		static BorderW := 4, PenW := 10
		
		; Create the necessary brushes
		pBrushBG := Gdip_BrushCreateSolid("0xFF226C22")
		pBrushFG := Gdip_BrushCreateSolid("0xFF6BAA6B")
		
		; Disable smoothing so the board is sharp
		Gdip_SetSmoothingMode(this.pGraphics, 3)
		
		; Background
		Gdip_FillRectangle(this.pGraphics, pBrushBG, 0, 0, this.Width, this.Height)
		
		; Bars, Horizontal then Vertical
		Gdip_FillRectangle(this.pGraphics, pBrushFG, this.Width/3 - BorderW/2, 0, BorderW, this.Height)
		Gdip_FillRectangle(this.pGraphics, pBrushFG, this.Width/3*2 - BorderW/2, 0, BorderW, this.Height)
		Gdip_FillRectangle(this.pGraphics, pBrushFG, 0, this.Height/3-2, this.Width, 4)
		Gdip_FillRectangle(this.pGraphics, pBrushFG, 0, this.Height/3*2-2, this.Width, 4)
		
		; Enable smoothing so the pieces aren't jagged
		Gdip_SetSmoothingMode(this.pGraphics, 4)
		pPen := Gdip_CreatePen(0xFF000000, PenW)
		
		; Draw the pieces
		for y, Row in this.Board
		{
			for x, Player in Row
			{
				if (Player == "X")
				{
					; \ then /
					Gdip_DrawLine(this.pGraphics, pPen
					, (this.Width/3*(x-1)) + PenW/2 + BorderW/2,     (this.Height/3*(y-1)) + PenW/2 + BorderW/2
					, (this.Width/3*x    ) - PenW/2 - BorderW/2 - 1, (this.Height/3*y    ) - PenW/2 - BorderW/2 - 1)
					Gdip_DrawLine(this.pGraphics, pPen
					, (this.Width/3*x    ) - PenW/2 - BorderW/2 - 1, (this.Height/3*(y-1)) + PenW/2 + BorderW/2
					, (this.Width/3*(x-1)) + PenW/2 + BorderW/2,     (this.Height/3*y    ) - PenW/2 - BorderW/2 - 1)
				}
				else if (Player == "O")
				{
					Gdip_DrawEllipse(this.pGraphics, pPen
					, (this.Width/3*(x-1)) + PenW/2 + BorderW/2, (this.Height/3*(y-1)) + PenW/2 + BorderW/2
					, this.Width/3 - PenW - BorderW - 1, this.Height/3 - PenW - BorderW - 1)
				}
			}
		}
		
		; Draw the particles
		for i, Particle in this.Particles
			Particle.Draw(this.pGraphics)
		
		; Clean up our GDI+ objects
		Gdip_DeletePen(pPen)
		Gdip_DeleteBrush(pBrushBG)
		Gdip_DeleteBrush(pBrushFG)
	}
	
	CheckWin()
	{
		for i, Player in ["X", "O"]
		{
			; Check for vertical wins
			Loop, 3 {
				if (this.Board[1, A_Index] == Player
					&& this.Board[2, A_Index] == Player
					&& this.Board[3, A_Index] == Player)
					return Player
			}
			
			; Check for horizontal wins
			Loop, 3 {
				if (this.Board[A_Index, 1] == Player
					&& this.Board[A_Index, 2] == Player
					&& this.Board[A_Index, 3] == Player)
					return Player
			}
			
			; Check for diagonal wins, \ then /
			if (this.Board[1, 1] == Player
				&& this.Board[2, 2] == Player
				&& this.Board[3, 3] == Player)
				return Player
			if (this.Board[1, 3] == Player
				&& this.Board[2, 2] == Player
				&& this.Board[3, 1] == Player)
				return Player
		}
		
		; Check if there's still a space for the next turn
		for y, Row in this.Board
			for x, Tile in Row
				if (Tile == "")
					return False
		
		; If there was not it's a tie
		return "Tie"
	}
	
	SpawnParticle()
	{
		static Options := [Star, Rect]
		
		; Pick a random particle type to spawn
		p := Options[Rand(1, Options.Length())]
		
		; Add the new particle to our internal list
		this.Particles.Push(new p(
		( LTrim Join Comments
			this.Width  / 2,         ; x
			this.Height / 2,         ; y
			Rand( -6.28,  6.28),     ; r
			Rand( -5.0,   5.0 ),     ; sx
			Rand(-10.0, -30.0 ),     ; sy
			Rand( -0.1,   0.1 ),     ; sr
			Rand(0x000000, 0xFFFFFF) ; Color
		)))
	}
}

class Star extends Particle
{
	Points :=
	( LTrim Join
	[
		[20/2 * cos(0.628 * 0), 20/2 * sin(0.628 * 0)],
		[20/4 * cos(0.628 * 1), 20/4 * sin(0.628 * 1)],
		[20/2 * cos(0.628 * 2), 20/2 * sin(0.628 * 2)],
		[20/4 * cos(0.628 * 3), 20/4 * sin(0.628 * 3)],
		[20/2 * cos(0.628 * 4), 20/2 * sin(0.628 * 4)],
		[20/4 * cos(0.628 * 5), 20/4 * sin(0.628 * 5)],
		[20/2 * cos(0.628 * 6), 20/2 * sin(0.628 * 6)],
		[20/4 * cos(0.628 * 7), 20/4 * sin(0.628 * 7)],
		[20/2 * cos(0.628 * 8), 20/2 * sin(0.628 * 8)],
		[20/4 * cos(0.628 * 9), 20/4 * sin(0.628 * 9)]
	]
	)
}

class Rect extends Particle
{
	Points :=
	( LTrim Join
	[
		[-20/2, -10/2],
		[-20/2,  10/2],
		[ 20/2,  10/2],
		[ 20/2, -10/2]
	]
	)
}

class Particle
{
	Points := []
	Origin := [0, 0]
	
	__New(x, y, r, sx, sy, sr, c)
	{
		this.x := x
		this.y := y
		this.r := r
		
		this.sx := sx
		this.sy := sy
		this.sr := sr
		
		this.c := c
	}
	
	GetRotated()
	{
		Rotated := []
		
		; https://stackoverflow.com/a/22491252
		for i, Point in this.Points
		{
			x1 := Point[1] - this.Origin[1]
			y1 := Point[2] - this.Origin[2]
			
			x2 := x1 * Cos(this.r) - y1 * Sin(this.r)
			y2 := x1 * Sin(this.r) + y1 * Cos(this.r)
			
			Rotated.Push([x2 + this.Origin[1], y2 + this.Origin[2]])
		}
		
		return Rotated
	}
	
	Step()
	{
		this.x += this.sx
		this.y += this.sy
		this.r += this.sr
		this.sy += 1
	}
	
	Draw(pGraphics)
	{
		; Get a list of rotated and translated points
		; compatible with Gdip_FillPolygon
		for i, Point in this.GetRotated()
			TextPoints .= "|" Point[1] + this.x "," Point[2] + this.y
		
		; Draw the polygon
		pBrush := Gdip_BrushCreateSolid(0xFF000000 | this.c)
		Gdip_FillPolygon(pGraphics, pBrush, SubStr(TextPoints, 2))
		Gdip_DeleteBrush(pBrush)
	}
}

Rand(Min, Max)
{
	Random, Rand, Min, Max
	return Rand
}
