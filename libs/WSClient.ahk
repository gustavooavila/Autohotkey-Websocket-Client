#Include %A_LineFile%\..\Crypto.ahk
#Include %A_LineFile%\..\WSDataFrame.ahk
#Include %A_LineFile%\..\Buffer.ahk
#Include %A_LineFile%\..\EventEmitter.ahk
#Include %A_LineFile%\..\HTTPClient.ahk


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


class WSClient extends SocketTCP
{
    PendingFragmentedRequest := 0

    HandleRequest(Request) {
        this.OnRequest.Call(Request)
    }

       OnRecv(ByRef message, length) {
                                  
        VarSetCapacity(Data, length + 1) ; One extra byte, so we can null terminate TEXT messages
        DllCall("RtlMoveMemory", "Ptr", &Data, "Ptr", &message, "UInt", length) 

        Request := new WSRequest(&Data, length)

        if (Request.Opcode & 0x10) {
            ; Control frame, skip fragmentation handling

            this.HandleRequest(Request)            
        }
        else if (Request.Opcode != 0 && Request.Final) {
            ; Opcode that can be fragmented, but this is the final request of the fragmented message.
            ; Meaning that this is both the start and end of a fragmented message, making it the 
            ;  only fragment of that message.

            this.HandleRequest(Request)
        }
        else {
            ; The start or middle/end of a fragmented request

            if (IsObject(this.PendingFragmentedRequest)) {
                ; Middle/end of a fragmented request

                this.PendingFragmentedRequest.Update(Request)
                
                if (this.PendingFragmentedRequest.Final) {
                    ; Middle *and* end of a fragmented request

                    this.HandleRequest(this.PendingFragmentedRequest)
                    this.PendingFragmentedRequest := 0
                }

                ; else { middle of fragmented request }
            }
            else {
                ; Start of a fragmented request

                if (Request.Opcode = 0) {
                    Throw Exception("The server replied with a fragmented request starting with an opcode of 0")
                }

                this.PendingFragmentedRequest := new WSFragmentedRequest(Request)
            }
        }
    }

    SendFrame(Opcode, pMessageBuffer := 0, MessageSize := 0) {
        Response := new WSResponse(Opcode, pMessageBuffer, MessageSize)
        ResponseBuffer := Response.Encode()

        this.Send(ResponseBuffer.GetPointer(), ResponseBuffer.Length)
    }

    SendText(Message) {
        MessageSize := StrPut(Message, "UTF-8") - 1
        VarSetCapacity(MessageBuffer, MessageSize)
        StrPut(Message, &MessageBuffer, MessageSize, "UTF-8")

        this.SendFrame(WSOpcodes.Text, &MessageBuffer, MessageSize)
    }
}
