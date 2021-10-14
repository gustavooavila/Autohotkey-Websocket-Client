#Persistent
#SingleInstance, force
SetBatchLines, -1

global Console := new CConsole()
Console.hotkey := "^+c"  ; to show the console
Console.show()

ws := new WSSession(Func("received"), "172.18.76.106", 8080)

Sleep, 1000
ws.SendText("Hello world!")

return

received(Session, Response)
{   
    console.log(Response)

    if (Response.DataType = "Text") {
        Console.log(Response.GetMessage())
    }
}

Esc::ExitApp

#include, %A_ScriptDir%\..\..\libs
#include, CConsole.ahk
#include WSSession.ahk
