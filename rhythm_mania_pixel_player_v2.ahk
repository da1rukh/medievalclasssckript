#Requires AutoHotkey >=2.0
#SingleInstance Force
; =============================================================================
; Пиксельный помощник для вертикальных ритм-игр (стиль osu!mania и аналоги).
; Настраивается под любую игру: цвета нот, полосы удержания, координаты линий.
;
; ВАЖНО: автоматизация может нарушать правила игры и привести к бану.
; Используйте только там, где это разрешено (офлайн, свои режимы, и т.д.).
; =============================================================================

global g_Running := false
global g_Lanes := []
global g_Config := Map()

LoadDefaultConfig()
ApplyConfigToLanes()
CoordMode("Pixel", "Screen")

; --- Горячие клавиши ---
F1:: {
    global g_Running
    g_Running := !g_Running
    TrayTip(g_Running ? "Запущен (F1 — стоп)" : "Остановлен", "Ритм-помощник", 1)
}
F2:: Reload
F3:: Edit  ; открыть этот скрипт в блокноте для правки настроек

A_TrayMenu.Delete()
A_TrayMenu.Add("Старт/стоп (F1)", (*) => Send("{F1}"))
A_TrayMenu.Add("Перезагрузить (F2)", (*) => Reload())
A_TrayMenu.Add()
A_TrayMenu.Add("Выход", (*) => ExitApp())
A_TrayMenu.Default := "Старт/стоп (F1)"

SetTimer(MainTick, g_Config["PollMs"])

MainTick() {
    global g_Running, g_Lanes
    if !g_Running
        return
    for lane in g_Lanes
        lane.Tick()
}

return

; =============================================================================
; НАСТРОЙКИ (меняйте под свою игру и разрешение)
; =============================================================================
LoadDefaultConfig() {
    global g_Config
    ; Режим координат: "Screen" — весь экран; "Client" — относительно окна игры
    g_Config["CoordMode"] := "Screen"
    ; Заголовок окна (часть имени). Пусто = не привязываться к окну.
    g_Config["GameWindowTitle"] := ""  ; например "osu!" или "StepMania"

    ; Глобальная линия прицела по Y (пиксель, куда «падают» ноты в момент нажатия)
    g_Config["HitLineY"] := 720
    ; Опрос пикселей (мс). 6 мс ≈ 167 Гц — ближайшее к 165 Гц при целых миллисекундах (SetTimer не дробит).
    ; Ниже — выше нагрузка на CPU; реальный шаг таймера Windows часто ~1 мс при timeBeginPeriod(1).
    g_Config["PollMs"] := 6
    ; Допуск по цвету (0–255 на каждый канал R,G,B)
    g_Config["ColorTolerance"] := 35
    ; Минимальная длительность удержания клавиши для «тапа» (мс), чтобы игра успела зарегистрировать
    g_Config["MinTapHoldMs"] := 28
    ; Сглаживание: не отпускать сразу, если цвет мигнул на 1 кадр
    g_Config["ReleaseDebounceMs"] := 40

    ; Каждая полоса: свой X на линии прицела, своя клавиша, свои цвета в формате 0xRRGGBB
    ; noteColor — обычная нота; holdColor — полоса удержания (0 = только тапы по noteColor)
    ; Если holdColor задан и отличается, при совпадении hold — зажатие до исчезновения hold
    g_Config["Lanes"] := [
        Map("key", "d", "scanX", 540,  "noteColor", 0x6EC5FF, "holdColor", 0x3A9FCC),
        Map("key", "f", "scanX", 640,  "noteColor", 0x6EC5FF, "holdColor", 0x3A9FCC),
        Map("key", "j", "scanX", 740,  "noteColor", 0xFF6E9A, "holdColor", 0xCC3A6E),
        Map("key", "k", "scanX", 840,  "noteColor", 0xFF6E9A, "holdColor", 0xCC3A6E),
    ]
}

ApplyConfigToLanes() {
    global g_Lanes, g_Config
    g_Lanes := []
    baseY := g_Config["HitLineY"]
    tol := g_Config["ColorTolerance"]
    mode := g_Config["CoordMode"]
    title := g_Config["GameWindowTitle"]
    minTap := g_Config["MinTapHoldMs"]
    debounce := g_Config["ReleaseDebounceMs"]

    for item in g_Config["Lanes"] {
        hold := item.Has("holdColor") ? item["holdColor"] : 0
        g_Lanes.Push(RhythmLane(
            item["key"],
            item["scanX"],
            baseY,
            item["noteColor"],
            hold,
            tol,
            mode,
            title,
            minTap,
            debounce
        ))
    }
}

class RhythmLane {
    __New(key, scanX, scanY, noteColor, holdColor, tolerance, coordMode, winTitle, minTapMs, releaseDebounceMs) {
        this.key := key
        this.scanX := scanX
        this.scanY := scanY
        this.noteColor := noteColor
        this.holdColor := holdColor
        this.tolerance := tolerance
        this.coordMode := coordMode
        this.winTitle := winTitle
        this.minTapMs := minTapMs
        this.releaseDebounceMs := releaseDebounceMs

        this._keyDown := false
        this._holdActive := false
        this._tapPressTick := 0
        this._lastSeen := 0
        this._lastReleaseCandidate := 0
    }

    Tick() {
        if !this._UpdateOrigin()
            return

        px := this.scanX + this._ox
        py := this.scanY + this._oy
        if !PixelGetColor(&rgb, px, py, "RGB") {
            return
        }

        now := A_TickCount
        holdMatch := (this.holdColor != 0) && ColorWithin(rgb, this.holdColor, this.tolerance)
        noteMatch := ColorWithin(rgb, this.noteColor, this.tolerance)

        if holdMatch {
            this._lastSeen := now
            this._lastReleaseCandidate := 0
            if !this._keyDown {
                Send("{" this.key " down}")
                this._keyDown := true
            }
            this._holdActive := true
            return
        }

        if this._holdActive && !holdMatch {
            ; конец удержания по цвету полосы
            this._holdActive := false
            if this._keyDown {
                Send("{" this.key " up}")
                this._keyDown := false
            }
        }

        if noteMatch {
            this._lastSeen := now
            this._lastReleaseCandidate := 0
            if !this._keyDown {
                Send("{" this.key " down}")
                this._keyDown := true
                this._tapPressTick := now
            }
            return
        }

        ; Нет совпадения: отпускаем с дебаунсом (тап)
        if this._keyDown && !this._holdActive {
            if this._lastReleaseCandidate = 0
                this._lastReleaseCandidate := now
            else if (now - this._lastReleaseCandidate) >= this.releaseDebounceMs {
                if (now - this._tapPressTick) >= this.minTapMs {
                    Send("{" this.key " up}")
                    this._keyDown := false
                }
                this._lastReleaseCandidate := 0
            }
        } else {
            this._lastReleaseCandidate := 0
        }
    }

    _UpdateOrigin() {
        this._ox := 0, this._oy := 0
        if this.coordMode != "Client" || this.winTitle = ""
            return true
        if !WinExist(this.winTitle)
            return false
        WinGetClientPos(&cx, &cy,,, this.winTitle)
        this._ox := cx
        this._oy := cy
        return true
    }
}

ColorWithin(got, want, tol) {
    gr := (got >> 16) & 0xFF, gg := (got >> 8) & 0xFF, gb := got & 0xFF
    wr := (want >> 16) & 0xFF, wg := (want >> 8) & 0xFF, wb := want & 0xFF
    return Abs(gr - wr) <= tol && Abs(gg - wg) <= tol && Abs(gb - wb) <= tol
}
