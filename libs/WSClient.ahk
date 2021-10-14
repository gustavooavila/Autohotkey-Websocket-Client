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
        
        this.HTTP := new HTTPClient(this.host, this.port, ObjBindMethod(this, "HandleHTTP"))

        this.DoHandshake()
    }
    
    DoHandshake()
    {
        console.log("only this once")

        UpgradeRequest := new HTTPRequest()

        this.key := createHandshakeKey()
        
        UpgradeRequest.headers["Host"] := this.host . ":" . this.port
        UpgradeRequest.headers["Origin"] := "http://" . this.host . ":" . this.port
        UpgradeRequest.headers["Connection"] := "Upgrade"
        UpgradeRequest.headers["Upgrade"] := "websocket"
        UpgradeRequest.headers["Sec-WebSocket-Key"] := this.key

        if(this.subprotocol)
        {
            request.headers["Sec-WebSocket-Protocol"] := this.subprotocol
        }

        UpgradeRequest.headers["Sec-WebSocket-Version"] := 13
        
        UpgradeRequest.method := "GET"
        UpgradeRequest.url := this.url

        this.HTTP.SendRequest(UpgradeRequest)
    }
    
    HandleHTTP(HTTP, Response)
    {
        if(Response.statuscode == 101)
        {
            if(sec_websocket_accept(this.key) != Response.headers["Sec-WebSocket-Accept"]) {
                console.log("WS Handshake error: key returned from server doesn't match.")
                return
            }
            
            ; "Suck the brains out" of the HTTPClient by stealing the socket from it, and having the socket
            ;  call back to us instead of the HTTP client

            this.Socket := HTTP.Socket
            this.Socket.OnRecv := ObjBindMethod(this, "HandleWS")
        }
        else
        {
            console.log(response.raw)
        }
    }
    
    HandleWS()
    {   
        DataSize := this.Socket.MsgLen()
        VarSetCapacity(Data, DataSize)

        this.Socket.Recv(Data, DataSize)

        res := new WSRequest(Data, DataSize)
        
        console.log(res)
        console.log(res.payload)
        return
    }
}
