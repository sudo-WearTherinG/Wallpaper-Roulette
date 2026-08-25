#Requires AutoHotkey v2.0
#SingleInstance Force

Target := A_ScriptDir "\WallpaperChanger.ahk"
Shortcut := A_Startup "\Wallpaper Changer.lnk"

if !FileExist(Target) {
    MsgBox "WallpaperChanger.ahk was not found.`n`nMake sure this file is in the same folder."
    ExitApp
}

if FileExist(Shortcut) {
    Result := MsgBox(
        "Wallpaper Changer is currently set to start with Windows.`n`n"
        . "Do you want to remove it from Windows Startup?",
        "Wallpaper Changer",
        "YesNo Icon?"
    )

    if (Result = "Yes") {
        try {
            FileDelete Shortcut
            MsgBox "Wallpaper Changer has been removed from Windows Startup."
        }
        catch {
            MsgBox "Could not remove the Startup shortcut."
        }
    }
}
else {
    Result := MsgBox(
        "Wallpaper Changer is not currently set to start with Windows.`n`n"
        . "Do you want to add it to Windows Startup?",
        "Wallpaper Changer",
        "YesNo Icon?"
    )

    if (Result = "Yes") {
        try {
            Shell := ComObject("WScript.Shell")
            Link := Shell.CreateShortcut(Shortcut)

            Link.TargetPath := Target
            Link.WorkingDirectory := A_ScriptDir
            Link.Description := "Wallpaper Changer"

            Link.Save()

            MsgBox "Wallpaper Changer will now start automatically when you sign in to Windows."
        }
        catch {
            MsgBox "Could not create the Startup shortcut."
        }
    }
}