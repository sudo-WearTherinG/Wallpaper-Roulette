#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; SETTINGS
; ============================================================

; Fade settings - tweak these if you want the fade slower/faster
FadeSteps := 14      ; how many steps in the fade (more = smoother)
FadeDelay := 7       ; ms between each step (bigger = slower fade)

; Wallpaper scaling mode:
;   Auto = automatically chooses Fill or Fit based on your monitor and image
;   Fill = fills the screen, cropping some of the image if necessary
;   Fit  = shows the entire image, which may add black bars
ScaleMode := "Auto"

; Auto mode: maximum percentage of the image that Fill is allowed to crop.
; Lower = more conservative (more images use Fit).
; Higher = more images use Fill.
AutoCropLimit := 12
; ============================================================

StateFile := A_ScriptDir "\wallpaper_state.txt"
ConfigFile := A_ScriptDir "\config.ini"
CacheFile := A_ScriptDir "\image-cache.ini"

; --- First-run setup: ask for the wallpaper folder if we don't have one saved yet ---
ImageFolder := ""
if FileExist(ConfigFile)
    ImageFolder := IniRead(ConfigFile, "Settings", "ImageFolder", "")

if (ImageFolder = "" || !DirExist(ImageFolder)) {
    MsgBox "Welcome! Choose the folder that contains your wallpaper images.", "Wallpaper Changer - Setup"

    ImageFolder := DirSelect(, 3, "Select your wallpaper folder")

    if (ImageFolder = "") {
        MsgBox "No folder selected. The script will now exit."
        ExitApp
    }

    ; Create config.ini
    IniWrite ImageFolder, ConfigFile, "Settings", "ImageFolder"

    ; Add readable per-image scaling instructions
    FileAppend "`n[ImageScale]`n", ConfigFile
    FileAppend "; Per-image scaling overrides.`n", ConfigFile
    FileAppend "; Format: image-name=Fit or Fill`n", ConfigFile
    FileAppend ";`n", ConfigFile
    FileAppend "; Lines starting with ';' are comments and are ignored.`n", ConfigFile
    FileAppend "; Remove the ';' to enable an override.`n", ConfigFile
    FileAppend ";`n", ConfigFile
    FileAppend "; Examples:`n", ConfigFile
    FileAppend ";wallhaven-x866ko=Fit`n", ConfigFile
    FileAppend ";wallhaven-x866ko=Fill`n", ConfigFile

    MsgBox "All set!`n`n"
        . "Press Win+W while on your Desktop to change the wallpaper.`n`n"
        . "Scaling:`n"
        . "• Auto is enabled by default.`n"
        . "• Auto checks your monitor resolution and calculates how much of each image would be cropped.`n"
        . "• If Fill would crop too much, it automatically uses Fit instead.`n"
        . "• The decision is cached for faster future wallpaper changes.`n`n"
        . "Manual overrides:`n"
        . "Open config.ini and use the [ImageScale] section.`n"
        . "Example:`n"
        . "wallhaven-x866ko=Fit`n"
        . "wallhaven-pojpdm=Fill`n`n"
        . "Lines starting with ';' are comments and are ignored.`n"
        . "Remove ';' to enable an override.`n`n"
        . "The cache automatically updates when an image changes or when you use a different monitor.",
        "Wallpaper Changer - Setup Complete"
}

; --- Hotkey: Win + W (only when Desktop is focused) ---
#HotIf WinActive("ahk_class Progman") or WinActive("ahk_class WorkerW")
#w:: ChangeWallpaper()
#HotIf

ChangeWallpaper() {
    global ImageFolder, StateFile, FadeSteps, FadeDelay, ConfigFile, ScaleMode, CacheFile, AutoCropLimit

    if !DirExist(ImageFolder) {
        MsgBox "Folder not found:`n" ImageFolder "`n`nDelete config.ini next to the script to choose a new folder."
        return
    }

    ; ========================================================
    ; LOAD IMAGE POOL
    ; ========================================================

    Pool := []

    if FileExist(StateFile) {
        Loop read, StateFile {
            if (A_LoopReadLine != "" && FileExist(A_LoopReadLine))
                Pool.Push(A_LoopReadLine)
        }
    }

    ; Rebuild pool when empty
    if (Pool.Length = 0) {
        Loop Files, ImageFolder "\*.jpg"
            Pool.Push(A_LoopFileFullPath)
        Loop Files, ImageFolder "\*.jpeg"
            Pool.Push(A_LoopFileFullPath)
        Loop Files, ImageFolder "\*.png"
            Pool.Push(A_LoopFileFullPath)
        Loop Files, ImageFolder "\*.bmp"
            Pool.Push(A_LoopFileFullPath)

        if (Pool.Length = 0) {
            MsgBox "No images (jpg/jpeg/png/bmp) found in:`n" ImageFolder
            return
        }
    }

    ; ========================================================
    ; PICK IMAGE
    ; ========================================================

    RandIndex := Random(1, Pool.Length)
    ChosenImage := Pool[RandIndex]
    Pool.RemoveAt(RandIndex)

    ; ========================================================
    ; DETERMINE SCALE MODE
    ; ========================================================

    FileName := RegExReplace(ChosenImage, "^.*\\")
    BaseName := RegExReplace(FileName, "\.[^.]+$")

    ; Global default
    CurrentScaleMode := ScaleMode

    ; Exact filename override
    SpecificOverride := IniRead(ConfigFile, "ImageScale", FileName, "")

    if (SpecificOverride != "") {
        CurrentScaleMode := SpecificOverride
    }
    else {
        ; Extensionless override
        BaseOverride := IniRead(ConfigFile, "ImageScale", BaseName, "")

        if (BaseOverride != "")
            CurrentScaleMode := BaseOverride
    }

    ; ========================================================
    ; LEVEL 2 AUTO MODE
    ; Monitor-aware crop calculation
    ; ========================================================

    FileSize := FileGetSize(ChosenImage)
    ModifiedTime := FileGetTime(ChosenImage, "M")

    CacheKey := FileName

    ; Current primary monitor dimensions
    MonitorWidth := A_ScreenWidth
    MonitorHeight := A_ScreenHeight

    ; --------------------------------------------------------
    ; CHECK CACHE
    ; --------------------------------------------------------

    CachedInfo := IniRead(CacheFile, "Images", CacheKey, "")

    if (CachedInfo != "") {
        Parts := StrSplit(CachedInfo, "|")

        ; New cache format:
        ; filesize|modifiedtime|monitorwidth|monitorheight|mode

        if (Parts.Length >= 5) {
            CachedSize := Parts[1]
            CachedTime := Parts[2]
            CachedMonitorWidth := Parts[3]
            CachedMonitorHeight := Parts[4]
            CachedMode := Parts[5]

            ; Cache is valid only if:
            ; - image hasn't changed
            ; - monitor resolution hasn't changed
            if (
                CachedSize = FileSize
                && CachedTime = ModifiedTime
                && CachedMonitorWidth = MonitorWidth
                && CachedMonitorHeight = MonitorHeight
            ) {
                if (StrLower(Trim(CurrentScaleMode)) = "Auto")
                    CurrentScaleMode := CachedMode
            }
        }
    }

    ; --------------------------------------------------------
    ; AUTO CALCULATION
    ; --------------------------------------------------------

    if (StrLower(Trim(CurrentScaleMode)) = "Auto") {

        Width := 0
        Height := 0

        try {
            ImageObj := ComObject("WIA.ImageFile")
            ImageObj.LoadFile(ChosenImage)

            Width := ImageObj.Width
            Height := ImageObj.Height
        }
        catch {
            Width := 0
            Height := 0
        }

        if (Width > 0 && Height > 0) {

            ; ------------------------------------------------
            ; Calculate how much of the image Fill would crop
            ; ------------------------------------------------

            ImageRatio := Width / Height
            MonitorRatio := MonitorWidth / MonitorHeight

            if (ImageRatio > MonitorRatio) {
                ; Image is wider than the monitor.
                ; Fill crops the left/right edges.

                VisibleWidth := Height * MonitorRatio
                CropPercent := (1 - (VisibleWidth / Width)) * 100
            }
            else {
                ; Image is taller/narrower than the monitor.
                ; Fill crops the top/bottom edges.

                VisibleHeight := Width / MonitorRatio
                CropPercent := (1 - (VisibleHeight / Height)) * 100
            }

            ; Prevent tiny floating-point errors
            if (CropPercent < 0)
                CropPercent := 0

            ; ------------------------------------------------
            ; Decide Fit or Fill
            ; ------------------------------------------------

            if (CropPercent <= AutoCropLimit)
                CurrentScaleMode := "Fill"
            else
                CurrentScaleMode := "Fit"

        }
        else {
            ; Couldn't read image dimensions.
            ; Safe fallback.
            CurrentScaleMode := "Fit"
        }

        ; ------------------------------------------------
        ; Save decision to cache
        ;
        ; Format:
        ; filesize|modifiedtime|monitorwidth|monitorheight|mode
        ; ------------------------------------------------

        IniWrite (
            FileSize
            "|" ModifiedTime
            "|" MonitorWidth
            "|" MonitorHeight
            "|" CurrentScaleMode
        ), CacheFile, "Images", CacheKey
    }

    ; ========================================================
    ; FADE TO BLACK
    ; ========================================================

    overlay := Gui("-Caption +ToolWindow +AlwaysOnTop")
    overlay.BackColor := "000000"
    overlay.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " NoActivate")
    WinSetTransparent(0, overlay)

    Loop FadeSteps {
        WinSetTransparent(Min(255, A_Index * (255 // FadeSteps)), overlay)
        Sleep FadeDelay
    }

    WinSetTransparent(255, overlay)

    ; ========================================================
    ; APPLY SCALE MODE
    ; ========================================================

    if (StrLower(Trim(CurrentScaleMode)) = "Fit")
        StyleCode := "6"
    else
        StyleCode := "10"

    RegWrite StyleCode, "REG_SZ", "HKEY_CURRENT_USER\Control Panel\Desktop", "WallpaperStyle"
    RegWrite "0", "REG_SZ", "HKEY_CURRENT_USER\Control Panel\Desktop", "TileWallpaper"

    ; ========================================================
    ; SET WALLPAPER
    ; ========================================================

    DllCall(
        "SystemParametersInfo",
        "UInt", 0x0014,
        "UInt", 0,
        "Str", ChosenImage,
        "UInt", 0x01 | 0x02
    )

    ; ========================================================
    ; FADE BACK IN
    ; ========================================================

    Loop FadeSteps {
        trans := 255 - (A_Index * (255 // FadeSteps))
        WinSetTransparent(Max(0, trans), overlay)
        Sleep FadeDelay
    }

    overlay.Destroy()

    ; ========================================================
    ; SAVE REMAINING POOL
    ; ========================================================

    if FileExist(StateFile)
        FileDelete StateFile

    for img in Pool
        FileAppend img "`n", StateFile
}