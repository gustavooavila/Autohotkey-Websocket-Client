#Include Socket.ahk

A := new ClientSocketTLS("balls")

A.Connect(["172.17.215.109", 8080])

A.StartTLS()