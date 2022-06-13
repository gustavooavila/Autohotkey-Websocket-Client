#Persistent
#SingleInstance, force
SetBatchLines, -1

global Console := new CConsole()
Console.hotkey := "^+c"  ; to show the console
Console.show()

ws := new WSSession("localhost", 8080)
ws.On("TEXT", Func("received"))

Sleep, 1000
ws.SendText("Hello world!")

return

received(Event)
{   
    Response := Event.Data

    console.log(Response)
    Console.log(Response.GetMessage())

    ;MsgBox, % Response.PayloadText
}

Esc::ExitApp

#include, %A_ScriptDir%\..\..\libs
#include, CConsole.ahk
#include WSSession.ahk
