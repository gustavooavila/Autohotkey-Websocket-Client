#include Crypto.ahk
#include WSDataFrame.ahk
#Include Buffer.ahk
#Include EventEmitter.ahk
#Include HTTPClient.ahk


createHandshakeKey()
{
    VarSetCapacity(CSPHandle, 8, 0)
    VarSetCapacity(RandomBuffer, 16, 0)
    DllCall("advapi32.dll\CryptAcquireContextA", "Ptr", &CSPHandle, "UInt", 0, "UInt", 0, "UInt", PROV_RSA_AES := 0x00000018,"UInt", CRYPT_VERIFYCONTEXT := 0xF0000000)
    DllCall("advapi32.dll\CryptGenRandom", "Ptr", NumGet(&CSPHandle, 0, "UInt64"), "UInt", 16, "Ptr", &RandomBuffer)
    DllCall("advapi32.dll\CryptReleaseContext", "Ptr", NumGet(&CSPHandle, 0, "UInt64"), "UInt", 0)
    
    return Base64_encode(&RandomBuffer, 16)
}

sec_websocket_accept(key)
{
    key := key . "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" ; Chosen by fair dice roll. Guaranteed to be random.
    sha1 := sha1_encode(key)
    pbHash := sha1[1]
    cbHash := sha1[2]
    b64 := Base64_encode(&pbHash, cbHash)
    return b64
}


class WSClient extends EventEmitter
{
    __New(host, port := 80, url := "/", subprotocol := "")
    {
        this.host := host
        this.port := port
        this.url := url
        this.subprotocol := subprotocol
        
        this.httpClient := new HTTPClient(this.host, this.port)
        
        this.httpClient.on("RECEIVED", objBindMethod(this, "handle"))
        this.httpClient.once("SEND", objBindMethod(this, "doHandshake"))
    }
    
    doHandshake(ByRef e)
    {
        console.log("only this once")
        this.key := createHandshakeKey()
        
        e.data.request.headers["Host"] := this.host . ":" . this.port
        e.data.request.headers["Origin"] := "http://" . this.host . ":" . this.port
        e.data.request.headers["Connection"] := "Upgrade"
        e.data.request.headers["Upgrade"] := "websocket"
        e.data.request.headers["Sec-WebSocket-Key"] := this.key
        if(this.subprotocol)
        {
            e.data.request.headers["Sec-WebSocket-Protocol"] := this.subprotocol
        }
        e.data.request.headers["Sec-WebSocket-Version"] := 13
        
        e.data.request.method := "GET"
        e.data.request.url := this.url
    }
    
    handle(ByRef e)
    {
        client := e.data.client
        request := e.data.request
        response := e.data.response
        if(client.websocket)
        {
            this.handleWS(client, e.data.data, e.data.len)
        }else
        {
            this.handleHTTP(request, response, client)
        }
    }
    
    handleHTTP(ByRef request, ByRef response, ByRef client)
    {
        if(response.statuscode == 101)
        {
            if(sec_websocket_accept(this.key) != response.headers["Sec-WebSocket-Accept"]) {
                console.log("WS Handshake error: key returned from server doesn't match.")
                return
            }
            client.websocket := True
        }
        else
        {
            console.log(response.raw)
        }
    }
    
    handleWS(ByRef client, ByRef data, len)
    {   
        res := new WSRequest(data, len)
        
        console.log(res)
        console.log(res.payload)
        return
    }
}
