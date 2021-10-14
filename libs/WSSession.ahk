#include HTTPClient.ahk
#include WSClient.ahk

class WSSession {
	 __New(OnRequest, host, port := 80, url := "/", subprotocol := "")
    {
        this.host := host
        this.port := port
        this.url := url
        this.subprotocol := subprotocol

		this.HandleWS := OnRequest.Bind(this)
        
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
            
			WS := this.HTTP
			ObjSetBase(WS, WSClient)
			this.WS := WS

			this.WS.OnRequest := this.HandleWS
        }
        else
        {
            console.log(response.raw)
        }
    }

	SendText(Message) {
		this.WS.SendText(Message)
	}
}