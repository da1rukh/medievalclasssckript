#Requires AutoHotkey >=2.0
#SingleInstance Force
; =============================================================================
; Пиксельный помощник для вертикальных ритм-игр (mania-стиль).
; Настройки: GUI + колорпик Windows + пипетка с экрана + INI рядом со скриптом.
;
; ВАЖНО: автоматизация может нарушать правила игры. Только там, где разрешено.
; =============================================================================

global g_Running := false
global g_Lanes := []
global g_Config := Map()
global g_SettingsGui := 0
global g_IniPath := A_ScriptDir "\rhythm_mania_pixel.ini"

LoadDefaultConfig()
if FileExist(g_IniPath)
    LoadConfigIni()
ApplyConfigToLanes()
CoordMode("Pixel", "Screen")

SetTimer(MainTick, g_Config["PollMs"])

; --- Горячие клавиши ---
F1:: {
    global g_Running
    g_Running := !g_Running
    TrayTip(g_Running ? "Запущен (F1 — стоп)" : "Остановлен", "Ритм-помощник", 1)
}
F2:: Reload
F3:: OpenSettingsGui()
^F3:: Edit

A_TrayMenu.Delete()
A_TrayMenu.Add("Настройки (F3)", OpenSettingsGui)
A_TrayMenu.Add("Старт/стоп (F1)", (*) => Send("{F1}"))
A_TrayMenu.Add("Перезагрузить (F2)", (*) => Reload())
A_TrayMenu.Add()
A_TrayMenu.Add("Выход", (*) => ExitApp())
A_TrayMenu.Default := "Настройки (F3)"

MainTick() {
    global g_Running, g_Lanes
    if !g_Running
        return
    for lane in g_Lanes
        lane.Tick()
}

return

; =============================================================================
; Конфиг по умолчанию
; =============================================================================
LoadDefaultConfig() {
    global g_Config
    g_Config["CoordMode"] := "Screen"
    g_Config["GameWindowTitle"] := ""
    g_Config["HitLineY"] := 720
    g_Config["PollMs"] := 6
    g_Config["ColorTolerance"] := 35
    g_Config["MinTapHoldMs"] := 28
    g_Config["ReleaseDebounceMs"] := 40
    g_Config["Lanes"] := [
        Map("key", "d", "scanX", 540, "noteColor", 0x6EC5FF, "holdColor", 0x3A9FCC),
        Map("key", "f", "scanX", 640, "noteColor", 0x6EC5FF, "holdColor", 0x3A9FCC),
        Map("key", "j", "scanX", 740, "noteColor", 0xFF6E9A, "holdColor", 0xCC3A6E),
        Map("key", "k", "scanX", 840, "noteColor", 0xFF6E9A, "holdColor", 0xCC3A6E),
    ]
}

LoadConfigIni() {
    global g_Config, g_IniPath
    sec := "Settings"
    g_Config["CoordMode"] := IniRead(g_IniPath, sec, "CoordMode", g_Config["CoordMode"])
    g_Config["GameWindowTitle"] := IniRead(g_IniPath, sec, "GameWindowTitle", g_Config["GameWindowTitle"])
    g_Config["HitLineY"] := Integer(IniRead(g_IniPath, sec, "HitLineY", g_Config["HitLineY"]))
    g_Config["PollMs"] := Integer(IniRead(g_IniPath, sec, "PollMs", g_Config["PollMs"]))
    g_Config["ColorTolerance"] := Integer(IniRead(g_IniPath, sec, "ColorTolerance", g_Config["ColorTolerance"]))
    g_Config["MinTapHoldMs"] := Integer(IniRead(g_IniPath, sec, "MinTapHoldMs", g_Config["MinTapHoldMs"]))
    g_Config["ReleaseDebounceMs"] := Integer(IniRead(g_IniPath, sec, "ReleaseDebounceMs", g_Config["ReleaseDebounceMs"]))
    n := Integer(IniRead(g_IniPath, sec, "LaneCount", g_Config["Lanes"].Length))
    if n < 1
        return
    lanes := []
    Loop n {
        i := A_Index
        ls := "Lane" i
        key := IniRead(g_IniPath, ls, "key", "x")
        scanX := Integer(IniRead(g_IniPath, ls, "scanX", "0"))
        nh := IniRead(g_IniPath, ls, "noteColor", "")
        hh := IniRead(g_IniPath, ls, "holdColor", "0")
        noteColor := IniHexToInt(nh, 0xFFFFFF)
        holdColor := (hh = "" || hh = "0") ? 0 : IniHexToInt(hh, 0)
        lanes.Push(Map("key", key, "scanX", scanX, "noteColor", noteColor, "holdColor", holdColor))
    }
    g_Config["Lanes"] := lanes
}

IniHexToInt(s, default := 0) {
    s := Trim(s)
    if s = ""
        return default
    if RegExMatch(s, "i)^0x")
        return Integer(s) & 0xFFFFFF
    return Integer("0x" s) & 0xFFFFFF
}

SaveConfigIni() {
    global g_Config, g_IniPath
    sec := "Settings"
    IniWrite(g_Config["CoordMode"], g_IniPath, sec, "CoordMode")
    IniWrite(g_Config["GameWindowTitle"], g_IniPath, sec, "GameWindowTitle")
    IniWrite(g_Config["HitLineY"], g_IniPath, sec, "HitLineY")
    IniWrite(g_Config["PollMs"], g_IniPath, sec, "PollMs")
    IniWrite(g_Config["ColorTolerance"], g_IniPath, sec, "ColorTolerance")
    IniWrite(g_Config["MinTapHoldMs"], g_IniPath, sec, "MinTapHoldMs")
    IniWrite(g_Config["ReleaseDebounceMs"], g_IniPath, sec, "ReleaseDebounceMs")
    IniWrite(g_Config["Lanes"].Length, g_IniPath, sec, "LaneCount")
    for i, lane in g_Config["Lanes"] {
        ls := "Lane" i
        IniWrite(lane["key"], g_IniPath, ls, "key")
        IniWrite(lane["scanX"], g_IniPath, ls, "scanX")
        IniWrite(Format("{:06X}", lane["noteColor"] & 0xFFFFFF), g_IniPath, ls, "noteColor")
        hc := lane.Has("holdColor") ? lane["holdColor"] : 0
        IniWrite(hc ? Format("{:06X}", hc & 0xFFFFFF) : "0", g_IniPath, ls, "holdColor")
    }
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

ApplyFromGuiAndRestartTimer() {
    global g_Config, g_SettingsGui
    if !g_SettingsGui
        return
    g := g_SettingsGui
    g_Config["CoordMode"] := g["DDLCoord"].Value = 2 ? "Client" : "Screen"
    g_Config["GameWindowTitle"] := g["EdTitle"].Value
    g_Config["HitLineY"] := Integer(g["EdHitY"].Value)
    g_Config["PollMs"] := Max(1, Integer(g["EdPoll"].Value))
    g_Config["ColorTolerance"] := Max(0, Integer(g["EdTol"].Value))
    g_Config["MinTapHoldMs"] := Max(0, Integer(g["EdMinTap"].Value))
    g_Config["ReleaseDebounceMs"] := Max(0, Integer(g["EdDebounce"].Value))
    SyncLanesFromListView()
    ApplyConfigToLanes()
    SetTimer(MainTick, 0)
    SetTimer(MainTick, g_Config["PollMs"])
}

SyncLanesFromListView() {
    global g_Config, g_SettingsGui
    lv := g_SettingsGui["LV"]
    lanes := []
    Loop lv.GetCount() {
        r := A_Index
        k := lv.GetText(r, 1)
        sx := lv.GetText(r, 2)
        nh := lv.GetText(r, 3)
        hh := lv.GetText(r, 4)
        lanes.Push(Map(
            "key", k,
            "scanX", Integer(sx),
            "noteColor", ParseHexColor(nh),
            "holdColor", (hh = "" || hh = "—" || hh = "0") ? 0 : ParseHexColor(hh),
        ))
    }
    g_Config["Lanes"] := lanes
}

SyncListViewFromConfig() {
    global g_Config, g_SettingsGui
    lv := g_SettingsGui["LV"]
    lv.Delete()
    for lane in g_Config["Lanes"] {
        h := lane.Has("holdColor") ? lane["holdColor"] : 0
        lv.Add(, lane["key"], lane["scanX"], ColorToHex(lane["noteColor"]), h ? ColorToHex(h) : "—")
    }
}

ParseHexColor(s) {
    s := Trim(s)
    if s = ""
        return 0
    if SubStr(s, 1, 2) != "0x"
        s := "0x" s
    return Integer(s) & 0xFFFFFF
}

ColorToHex(rgb) {
    return "0x" Format("{:06X}", rgb & 0xFFFFFF)
}

SetSwatch(ctrl, rgb) {
    rgb &= 0xFFFFFF
    r := (rgb >> 16) & 0xFF, g := (rgb >> 8) & 0xFF, b := rgb & 0xFF
    ctrl.Opt("+Background" Format("{:02x}{:02x}{:02x}", r, g, b))
}

; =============================================================================
; GUI настроек
; =============================================================================
OpenSettingsGui(*) {
    global g_SettingsGui, g_Config
    if g_SettingsGui {
        g_SettingsGui.Show()
        g_SettingsGui.Restore()
        WinActivate(g_SettingsGui.Hwnd)
        return
    }
    g := Gui("+Resize", "Ритм-помощник — настройки")
    g.SetFont("s10", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Escape", (*) => g.Hide())

    tab := g.Add("Tab3", "w560 h520 vTab", ["Общее", "Полосы и цвета"])

    tab.UseTab(1)
    g.Add("Text", "xm+12 ym+36 Section", "Режим координат:")
    ddl := g.Add("DropDownList", "w320 vDDLCoord", ["Экран (Screen)", "Окно (Client)"])
    ddl.Value := g_Config["CoordMode"] = "Client" ? 2 : 1

    g.Add("Text", "xs", "Заголовок окна игры (для Client, часть имени):")
    g.Add("Edit", "w520 vEdTitle", g_Config["GameWindowTitle"])

    g.Add("Text", "xs", "Линия прицела Y:")
    g.Add("Edit", "w100 vEdHitY Number", g_Config["HitLineY"])
    g.Add("Text", "yp x+20", "Опрос (мс, ~167 при 6):")
    g.Add("Edit", "w80 vEdPoll Number", g_Config["PollMs"])

    g.Add("Text", "xs", "Допуск цвета (0–255):")
    g.Add("Edit", "w80 vEdTol Number", g_Config["ColorTolerance"])
    g.Add("Text", "yp x+20", "Мин. тап (мс):")
    g.Add("Edit", "w80 vEdMinTap Number", g_Config["MinTapHoldMs"])
    g.Add("Text", "yp x+20", "Дебаунс отпускания (мс):")
    g.Add("Edit", "w80 vEdDebounce Number", g_Config["ReleaseDebounceMs"])

    g.Add("Button", "xs w180", "Применить к скрипту").OnEvent("Click", BtnApplyClick)
    g.Add("Button", "yp w180 x+12", "Сохранить в INI").OnEvent("Click", BtnSaveIniClick)
    g.Add("Button", "yp w180 x+12", "Загрузить из INI").OnEvent("Click", BtnLoadIniClick)

    tab.UseTab(2)
    g.Add("Text", "xm+12 ym+36 Section", "Список полос (клавиша, X на линии, цвета в hex). Выделите строку для пипетки / палитры.")

    lv := g.Add("ListView", "w520 r12 vLV +Grid -Multi", ["Клавиша", "scanX", "Нота", "Hold"])
    lv.OnEvent("Click", LvSelectHandler)
    lv.OnEvent("ItemFocus", LvSelectHandler)

    for lane in g_Config["Lanes"] {
        h := lane.Has("holdColor") ? lane["holdColor"] : 0
        lv.Add(, lane["key"], lane["scanX"], ColorToHex(lane["noteColor"]), h ? ColorToHex(h) : "—")
    }

    g.Add("Button", "xs w120 Section", "Добавить полосу").OnEvent("Click", BtnAddLane)
    g.Add("Button", "yp w120 x+8", "Удалить строку").OnEvent("Click", BtnDelLane)

    g.Add("Text", "xs", "Предпросмотр:")
    swN := g.Add("Text", "w56 h28 Border vSwNote")
    swH := g.Add("Text", "w56 h28 Border xp+64 vSwHold")

    g.Add("Text", "xs", "Нота (hex):")
    g.Add("Edit", "w200 vEdNoteHex")
    g.Add("Button", "yp w130 x+8", "Палитра…").OnEvent("Click", (*) => PickColorDialog("note"))
    g.Add("Button", "yp w130 x+8", "Пипетка").OnEvent("Click", (*) => PickColorScreen("note"))

    g.Add("Text", "xs", "Hold (hex, пусто / 0 = только тап):")
    g.Add("Edit", "w200 vEdHoldHex")
    g.Add("Button", "yp w130 x+8", "Палитра…").OnEvent("Click", (*) => PickColorDialog("hold"))
    g.Add("Button", "yp w130 x+8", "Пипетка").OnEvent("Click", (*) => PickColorScreen("hold"))

    g.Add("Text", "xs", "Клавиша (одна буква / символ):")
    g.Add("Edit", "w80 vEdKey")
    g.Add("Text", "yp x+16", "scanX:")
    g.Add("Edit", "w100 vEdScanX Number")

    g.Add("Button", "xs w240", "Записать в выделенную строку").OnEvent("Click", BtnWriteRowClick)

    tab.UseTab()

    g.Add("Text", "xm+8", "F1 — старт/стоп · F3 — это окно · Ctrl+F3 — правка кода скрипта")
    g.Show("w600 h620")
    global g_SettingsGui
    g_SettingsGui := g
    if lv.GetCount()
        lv.Modify(1, "Select Focus Vis")
    LvSelectHandler(lv)
}

LvSelectHandler(lv, *) {
    global g_SettingsGui
    g := g_SettingsGui
    if !g
        return
    row := lv.GetNext(, "F")
    if !row {
        g["EdNoteHex"].Value := ""
        g["EdHoldHex"].Value := ""
        return
    }
    k := lv.GetText(row, 1)
    sx := lv.GetText(row, 2)
    nh := lv.GetText(row, 3)
    hh := lv.GetText(row, 4)
    g["EdKey"].Value := k
    g["EdScanX"].Value := sx
    g["EdNoteHex"].Value := nh
    g["EdHoldHex"].Value := hh = "—" ? "" : hh
    SetSwatch(g["SwNote"], ParseHexColor(nh))
    SetSwatch(g["SwHold"], hh != "—" && hh != "" ? ParseHexColor(hh) : 0x222222)
}

GetFocusedLaneRow() {
    global g_SettingsGui
    return g_SettingsGui["LV"].GetNext(, "F")
}

BtnAddLane(*) {
    global g_Config, g_SettingsGui
    SyncLanesFromListView()
    g_Config["Lanes"].Push(Map("key", "a", "scanX", 400, "noteColor", 0xFFFFFF, "holdColor", 0))
    SyncListViewFromConfig()
    n := g_SettingsGui["LV"].GetCount()
    if n
        g_SettingsGui["LV"].Modify(n, "Select Focus Vis")
    LvSelectHandler(g_SettingsGui["LV"])
}

BtnDelLane(*) {
    global g_Config, g_SettingsGui
    lv := g_SettingsGui["LV"]
    row := lv.GetNext(, "F")
    if !row
        return
    SyncLanesFromListView()
    g_Config["Lanes"].RemoveAt(row)
    SyncListViewFromConfig()
    if lv.GetCount() {
        nr := Min(row, lv.GetCount())
        lv.Modify(nr, "Select Focus Vis")
    }
    LvSelectHandler(lv)
}

BtnWriteRowClick(*) {
    row := GetFocusedLaneRow()
    if !row {
        MsgBox("Выделите строку в списке полос.", "Запись", "Icon!")
        return
    }
    ApplyFieldsToListViewRow(row)
}

ApplyFieldsToListViewRow(row) {
    global g_SettingsGui
    g := g_SettingsGui
    lv := g["LV"]
    k := Trim(g["EdKey"].Value)
    if k = ""
        k := "x"
    else
        k := SubStr(k, 1, 1)
    sx := Integer(g["EdScanX"].Value)
    nh := Trim(g["EdNoteHex"].Value)
    if nh = ""
        nh := "0xFFFFFF"
    hh := Trim(g["EdHoldHex"].Value)
    hhex := hh = "" || hh = "0" ? "—" : (RegExMatch(hh, "i)^0x") ? hh : "0x" hh)
    nhex := RegExMatch(nh, "i)^0x") ? nh : "0x" nh
    if !row {
        lv.Add(, k, sx, nhex, hhex)
    } else {
        lv.Modify(row,, k, sx, nhex, hhex)
    }
    SetSwatch(g["SwNote"], ParseHexColor(nhex))
    SetSwatch(g["SwHold"], hhex = "—" ? 0x222222 : ParseHexColor(hhex))
}

BtnApplyClick(*) {
    ApplyFromGuiAndRestartTimer()
    TrayTip("Сохранено в памяти", "Параметры применены (таймер перезапущен)", 1)
}

BtnSaveIniClick(*) {
    global g_IniPath
    ApplyFromGuiAndRestartTimer()
    SaveConfigIni()
    TrayTip("INI", "Записано в:`n" g_IniPath, 2)
}

BtnLoadIniClick(*) {
    global g_IniPath, g_Config, g_SettingsGui
    if !FileExist(g_IniPath) {
        MsgBox("Файл не найден:`n" g_IniPath, "INI", "Icon!")
        return
    }
    LoadConfigIni()
    g := g_SettingsGui
    g["DDLCoord"].Value := g_Config["CoordMode"] = "Client" ? 2 : 1
    g["EdTitle"].Value := g_Config["GameWindowTitle"]
    g["EdHitY"].Value := g_Config["HitLineY"]
    g["EdPoll"].Value := g_Config["PollMs"]
    g["EdTol"].Value := g_Config["ColorTolerance"]
    g["EdMinTap"].Value := g_Config["MinTapHoldMs"]
    g["EdDebounce"].Value := g_Config["ReleaseDebounceMs"]
    SyncListViewFromConfig()
    if g["LV"].GetCount()
        g["LV"].Modify(1, "Select Focus Vis")
    LvSelectHandler(g["LV"])
    ApplyFromGuiAndRestartTimer()
    TrayTip("INI", "Загружено из файла", 1)
}

PickColorDialog(which) {
    global g_SettingsGui
    row := GetFocusedLaneRow()
    if !row {
        MsgBox("Сначала выделите полосу в списке.", "Цвет", "Icon!")
        return
    }
    cur := which = "note"
        ? ParseHexColor(g_SettingsGui["EdNoteHex"].Value)
        : ParseHexColor(g_SettingsGui["EdHoldHex"].Value)
    if which = "hold" && (g_SettingsGui["EdHoldHex"].Value = "")
        cur := 0x404040
    picked := ChooseColorW(cur, g_SettingsGui.Hwnd)
    if picked = ""
        return
    hex := ColorToHex(picked)
    if which = "note"
        g_SettingsGui["EdNoteHex"].Value := hex
    else
        g_SettingsGui["EdHoldHex"].Value := hex
    SetSwatch(which = "note" ? g_SettingsGui["SwNote"] : g_SettingsGui["SwHold"], picked)
}

PickColorScreen(which) {
    global g_SettingsGui
    row := GetFocusedLaneRow()
    if !row {
        MsgBox("Выделите полосу в списке.", "Пипетка", "Icon!")
        return
    }
    g_SettingsGui.Minimize()
    TrayTip("Пипетка", "Наведите курсор и нажмите ЛКМ по пикселю в игре", 1)
    Sleep(350)
    KeyWait("LButton", "D")
    KeyWait("LButton")
    MouseGetPos(&mx, &my)
    if !PixelGetColor(&rgb, mx, my, "RGB") {
        g_SettingsGui.Restore()
        TrayTip("Ошибка", "Не удалось прочитать пиксель", 2)
        return
    }
    hex := ColorToHex(rgb)
    if which = "note"
        g_SettingsGui["EdNoteHex"].Value := hex
    else
        g_SettingsGui["EdHoldHex"].Value := hex
    SetSwatch(which = "note" ? g_SettingsGui["SwNote"] : g_SettingsGui["SwHold"], rgb)
    g_SettingsGui.Restore()
    WinActivate(g_SettingsGui.Hwnd)
}

; =============================================================================
; Диалог выбора цвета Windows (ChooseColorW), без внешних библиотек
; =============================================================================
RgbToBGR(rgb) {
    rgb &= 0xFFFFFF
    return ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
}

BgrToRGB(bgr) {
    bgr &= 0xFFFFFF
    return ((bgr & 0xFF) << 16) | (bgr & 0xFF00) | ((bgr >> 16) & 0xFF)
}

ChooseColorW(initialRgb, hwndOwner := 0) {
    static cust := Buffer(64, 0)
    ccSize := A_PtrSize = 8 ? 72 : 36
    cc := Buffer(ccSize, 0)
    NumPut("UInt", ccSize, cc, 0)
    NumPut("Ptr", hwndOwner, cc, A_PtrSize = 8 ? 8 : 4)
    NumPut("Ptr", 0, cc, A_PtrSize = 8 ? 16 : 8)
    NumPut("UInt", RgbToBGR(initialRgb), cc, A_PtrSize = 8 ? 24 : 12)
    NumPut("Ptr", cust.Ptr, cc, A_PtrSize = 8 ? 32 : 16)
    ; CC_RGBINIT | CC_FULLOPEN | CC_ANYCOLOR
    NumPut("UInt", 0x103, cc, A_PtrSize = 8 ? 40 : 20)
    NumPut("Ptr", 0, cc, A_PtrSize = 8 ? 48 : 24)
    NumPut("Ptr", 0, cc, A_PtrSize = 8 ? 56 : 28)
    NumPut("Ptr", 0, cc, A_PtrSize = 8 ? 64 : 32)
    ; Явная проверка успеха — иначе #Warn Unreachable считает, что второй return недостижим.
    ok := DllCall("comdlg32\ChooseColorW", "ptr", cc.Ptr, "Int")
    if ok
        return BgrToRGB(NumGet(cc, A_PtrSize = 8 ? 24 : 12, "UInt") & 0xFFFFFF)
    return ""
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
