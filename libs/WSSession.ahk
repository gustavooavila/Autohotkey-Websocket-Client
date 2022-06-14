#Include %A_LineFile%\..\EventEmitter.ahk
#Include %A_LineFile%\..\HTTPClient.ahk
#Include %A_LineFile%\..\WSClient.ahk

class WSSession extends EventEmitter {
	; So, the whole idea behind a websocket is that we're converting a HTTP connection into a websocket connection, reusing the
        ;  existing connection. 
        ; Which means we either need our HTTP socket to understand websockets (which is just flat out a bad idea), or we need
    ;  to come up with a way to convert out HTTP socket into a websocket socket. Which is what this class does.
    
	; And this class accomplishes that. It acts as either an HTTP session, or a websocket session depening ong what's needed
        ;  at the moment. So it is an HTTP session until we switch to the websocket protocol, then it is a websocket session
    ;   from then one.
	
	; And since HTTPClient and WSClient both share the common base class of TCPSocket, and only depend on TCPSocket members, it is
        ;  perfectly safe to just swap WSClient in for the base class of an existing HTTPClient and have TCPSocket members work
        ;   just like before.
    ; Effectively casting a HTTPClient to a WSClient.
    
    __New(host, port := 80, url := "/", subprotocol := "")
    {
        this.host := host
        this.port := port
        this.url := url
        this.subprotocol := subprotocol
        
		; At this point, our WSSession is just an HTTP session
        
        this.HTTP := new HTTPClient(this.host, this.port, ObjBindMethod(this, "HandleHTTP"))
        
        this.DoHandshake() ; Attempt to become a websocket session
    }
    
    DoHandshake()
    {
        UpgradeRequest := new HTTPRequest()
        
        this.key := createHandshakeKey()
        
        UpgradeRequest.headers["Host"] := this.host . ":" . this.port
        UpgradeRequest.headers["Origin"] := "http://" . this.host . ":" . this.port
        UpgradeRequest.headers["Connection"] := "Upgrade"
        UpgradeRequest.headers["Upgrade"] := "websocket"
        UpgradeRequest.headers["Sec-WebSocket-Key"] := this.key
        
        if(this.subprotocol)
        {
            UpgradeRequest.headers["Sec-WebSocket-Protocol"] := this.subprotocol
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
			; Server has given us the green light to become a websocket session
            
            if(sec_websocket_accept(this.key) != Response.headers["Sec-WebSocket-Accept"]) {
                Throw Exception("Handshake error: key returned from server doesn't match.")
            }
            
			WS := this.HTTP
			ObjSetBase(WS, WSClient) ; Cast our HTTPClient into our WSCient
			this.WS := WS
            
			; Fixup OnRequest so it'll call our HandleWS instead of the (now dead) HTTPClient's OnRequest
			this.WS.OnRequest := ObjBindMethod(this, "HandleWS")
            
            this.OnCONNECT()
            this.emit("OnCONNECT")
        }
        else
        {
            ; Oops, something's wrong
            
			Throw Exception("Unexpected HTTP status code " Response.StatusCode)
        }
    }
    
	HandleWS(Response) {
		; Generic "websocket message" handler
		OpcodeName := WSOpcodes.ToString(Response.Opcode) ; Delegate to `OnOpcodeName()` methods if we've got them
        
		this["On" OpcodeName](Response)
		return this.Emit(OpcodeName, Response) ; Call any user handlers
    }
    
	OnPing(Response) {
		; To handle a PING, we just need to reply with a PONG containing the exact same application data as the pong
        
		this.WS.SendFrame(WSOpcodes.Pong, Response.pPayload, Response.PayloadSize)
        
		;console.log("Pong'd")
    }
    
	OnClose(Response) {
		; To handle a CLOSE, we just reply with a CLOSE and then close the socket
        
		this.WS.SendFrame(WSOpcodes.Close)
        
		this.WS.Disconnect()
        
		;console.log("Closed")
    }
    
    Disconnect() {
        this.WS.SendFrame(WSOpcodes.Close)
        this.WS.Disconnect()
    }
    
	SendText(Message) {
		this.WS.SendText(Message)
    }
}