#Persistent
#SingleInstance, force
SetBatchLines, -1

global Console := new CConsole()
Console.hotkey := "^+c"  ; to show the console
Console.show()

ws := new WSClient("localhost", 8080)
ws.addListener("RECEIVED", Func("received"))
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
#include, HTTPClient.ahk
#include, WSClient.ahk