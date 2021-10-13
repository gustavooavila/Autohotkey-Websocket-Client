#include AHKsock.ahk
#Include Buffer.ahk
#Include EventEmitter.ahk
#Include URI.ahk

; this is a hack to allow AHKsock to accept BoundFunc as parameter for AHKsock_Connect and AHKsock_Listen
isFunc(param)
{
	fn := numGet(&(_ := Func("InStr").bind()), "Ptr")
	return (Func(param) || (isObject(param) && (numGet(&param, "Ptr") = fn)))
}

class SocketClient
{
    __New(socket) {
        this.socket := socket
    }
    
    ;TODO: clean up better, delete this object and all references
    
    Close(timeout = 5000) {
        AHKsock_Close(this.socket, timeout)
    }
    
    ;TODO: replace with message Queue
    
    SetData(data) {
        console.log("set data")
        this.data := data
    }
    sendBinary(byRef data) {
        if ((i := AHKsock_Send(this.socket, p, length - this.dataSent)) < 0) {
            console.log("sent binary data")
        }
    }
    TrySend() {
        if (!this.data || this.data == "")
        return false
        
        console.log("trysend")
        p := this.data.GetPointer()
        length := this.data.length
        
        this.dataSent := 0
        
        loop {
            if ((i := AHKsock_Send(this.socket, p, length - this.dataSent)) < 0) {
                if (i == -2) {
                return
                } else {
                    ; Failed to send
                    return
                }
            }
            if (i < length - this.dataSent) {
            this.dataSent += i
            } else {
                break
            }
        }
        this.dataSent := 0
        this.data := ""
        
        return true
    }
}

class HTTPClient extends EventEmitter
{
    __New(host, port) {
        this.host := host
        this.port := port
        this.requests := []
        
        If (i := AHKsock_Connect(this.host, this.port, objBindMethod(this, "handler")))
        {
            console.log("AHKsock_Connect() failed with return value = ", i," and ErrorLevel = ", ErrorLevel)
        }
    }
    
    handler(sEvent, iSocket = 0, sName = 0, sAddr = 0, sPort = 0, ByRef bData = 0, bNewDataLength = 0)
    {
        console.log(sEvent, iSocket)
        client := this.requests[iSocket]
        text := StrGet(&bData, "UTF-8")
        If (sEvent = "CONNECTED")
        {
            If (iSocket = -1)
            {
                Console.log("Client - AHKsock_Connect() failed.")
                return -1
            }
            this.requests[iSocket] := new SocketClient(iSocket)
            this.emit("CONNECTED", {client: client})
            
        } else if(sEvent = "RECEIVED")
        {
            if(client.websocket)
            {
                this.emit("RECEIVED", {client: client, data: bData,len: bNewDataLength})
                return
            }
            if (client.response)
            {
                ; Get data and append it to the existing response body
                client.response.bytesLeft -= StrLen(text)
                client.response.body := client.response.body . text
                response := client.response
            } else
            {
                ; Parse new response
                response := new HTTPResponse(text)
                length := response.headers["Content-Length"]
                response.bytesLeft := length + 0
                
                if (response.body) {
                    response.bytesLeft -= StrLen(response.body)
                }
            }
            if (response.bytesLeft <= 0)
            {
                response.done := true
            } else
            {
                client.response := response
            }
            
            if(response.done)
            {
                this.emit("RECEIVED", {client: client, response: response, request: client.request})
            }
        } else if(sEvent = "DISCONNECTED")
        {
            this.emit("DISCONNECTED", {client: client})
        } else if(sEvent = "SEND")
        {
            if(client.websocket)
            {
                this.emit("SEND", {client: client, message: text})
                return
            }
            request := new HTTPRequest()
            client.request := request
            this.emit("SEND", {client: client, request: request})
            client.SetData(request.Generate())
            client.TrySend()
        }
    }
}

class HTTPRequest
{
    __new(method := "GET", url := "/", headers := "")
    {
        if(headers == "")
        {
            headers := {}
        }
        this.method := method
        this.headers := headers
        this.url := url
        this.protocol := "HTTP/1.1"
    }
    
    Generate()
    {
        body := this.method . " " . this.url . " " . this.protocol . "`r`n"
        
        for key, value in this.headers {
            StringReplace,value,value,`n,,A
            StringReplace,value,value,`r,,A
            body .= key . ": " . value . "`r`n"
        }
        body .= "`r`n`r`n"
        buffer := new Buffer((StrLen(body) * 2))
        buffer.WriteStr(body)
        
        buffer.Done()
        
        return buffer
    }
}

class HTTPResponse
{
    __new(data)
    {
        if (data)
        this.Parse(data)
    }
    
    GetPathInfo(top)
    {
        results := []
        while (pos := InStr(top, " ")) {
            results.Insert(SubStr(top, 1, pos - 1))
            top := SubStr(top, pos + 1)
        }
        this.method := results[1]
        this.statuscode := Uri.Decode(results[2])
        this.protocol := top
    }
    
    Parse(data) {
        this.raw := data
        data := StrSplit(data, "`n`r")
        headers := StrSplit(data[1], "`n")
        this.body := LTrim(data[2], "`n")
        this.GetPathInfo(headers.Remove(1))
        this.headers := {}
        
        for i, line in headers {
            pos := InStr(line, ":")
            key := SubStr(line, 1, pos - 1)
            val := Trim(SubStr(line, pos + 1), "`n`r ")
            
            this.headers[key] := val
        }
    }
}