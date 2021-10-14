#Persistent
#SingleInstance, force
SetBatchLines, -1

global Console := new CConsole()
Console.hotkey := "^+c"  ; to show the console
Console.show()

ws := new WSSession(Func("received"), "172.18.76.106", 8080)
return

received(ByRef e)
{
    client := e.data.client
    response := e.data.response
    request := e.data.request
    
    console.log(response)
}

Esc::ExitApp

#include, %A_ScriptDir%\..\..\libs
#include, CConsole.ahk
#include WSSession.ahk
