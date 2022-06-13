/*
	this is where we hide the ugly code, Yeah it gets uglier...
	acording to the Websocket RFC: http://tools.ietf.org/html/rfc6455
	there's lots of bits that we need to scrub before we can get the message data
	according to ammount of data the message may be split in multiple data frames
	as well as change the format of the data frame
	
	
	Frame format:
	0               1               2               3               4    bytes
	0                   1                   2                   3
	0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
	+-+-+-+-+-------+-+-------------+-------------------------------+
	|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
	|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
	|N|V|V|V|       |S|             |   (if payload len==126/127)   |
	| |1|2|3|       |K|             |                               |
	+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
	|     Extended payload length continued, if payload len == 127  |
	+ - - - - - - - - - - - - - - - +-------------------------------+
	|                               |Masking-key, if MASK set to 1  |
	+-------------------------------+-------------------------------+
	| Masking-key (continued)       |          Payload Data         |
	+-------------------------------- - - - - - - - - - - - - - - - +
	:                     Payload Data continued ...                :
	+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
	|                     Payload Data continued ...                |
	+---------------------------------------------------------------+
	
	OpCodes: 
	0x8 Close
	0x9 Ping
	0xA Pong
	
	Payload data OpCodes:
	0x0 Continuation
	0x1 Text
	0x2 Binary
	
	
	
	references: 
	http://tools.ietf.org/html/rfc6455
	https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_servers
	https://www.iana.org/assignments/websocket/websocket.xhtml
	
	implementation references:
	Lua: https://github.com/lipp/lua-websockets/blob/master/src/websocket/frame.lua
	Python: https://github.com/aaugustin/websockets/blob/main/src/websockets/frames.py
	JS: https://github.com/websockets/ws/blob/master/lib/receiver.js
	JS: https://github.com/websockets/ws/blob/master/lib/sender.js
	
	when reading this code, keep in mind:
	1 - there's no way to read binary in AHK, only bytes at a time (so there's lots of AND masking going on)
	2 - arrays start at 1
*/

OpCodes := {CONTINUATION:0x0,TEXT:0x1,BINARY:0x2,CLOSE:0x8,PING:0x9,PONG:0xA}

class WSOpcodes {
		static CONTINUATION := 0x0
		static TEXT := 0x1
		static BINARY := 0x2
		static CLOSE := 0x8
		static PING := 0x9
		static PONG := 0xA

		ToString(Value) {
			for Name, NameValue in WSOpcodes {
				if (Value = NameValue) {
					return Name
				}
			}
		}
	}

/*
	MDN says: 
	"
	1. Read bits 9-15 (inclusive) and interpret that as an unsigned integer. If it's 125 or less, then that's the length; you're done. If it's 126, go to step 2. If it's 127, go to step 3.
	2. Read the next 16 bits and interpret those as an unsigned integer. You're done.
	3. Read the next 64 bits and interpret those as an unsigned integer. (The most significant bit must be 0.) You're done.
	"
	So unfortunatelly using NumGet UShort and UInt64 doesn't work...
*/
Uint16(a, b) {
	return a << 8 | b
}
Uint64(a, b, c, d) {
	return a << 24 | b << 16 | c << 8 | d    
}
Uint16ToUChar(c) {
	a := c >> 8
	b := c & 0xFF
	return [a, b]
}

Uint64ToUChar(e) {
	a := e >> 24
	b := e >> 16
	c := e >> 8
	d := c & 0xFF
	return [a, b, c, d]
}

class WSDataFrame{
	encode(message) {
		length := strlen(message)
		if(length < 125) {
			byteArr := [129, length]
			buf := new Buffer(length + 2)
			Loop, Parse, message
			byteArr.push(Asc(A_LoopField))
			VarSetCapacity(result, byteArr.Length())
			For, i, byte in byteArr
			NumPut(byte, result, A_Index - 1, "UInt")
			buf.Write(&result, length + 2)
		}
		return buf
	}
}

class ReadOnlyBufferBase {
	ReadString(Offset, Length := -1) {
		if (Length > 0) {
			return StrGet(this.pData + Offset, Length, "UTF-8")
		}
		else {
			return StrGet(this.pData + Offset, "UTF-8")
		}
	}
	
	__Call(MethodName, Params*) {
		if (RegexMatch(MethodName, "O)Read(\w+)", Read) && Read[1] != "String") {
			return NumGet(this.pData + 0, Params[1], Read[1])
		}
	}
}

MoveMemory(pTo, pFrom, Size) {
   DllCall("RtlMoveMemory", "Ptr", pTo, "Ptr", pFrom, "UInt", Size)
}

class WSRequest extends ReadOnlyBufferBase {
	__New(pData, DataLength){
		this.pData := pData
		this.DataLength := DataLength

		this.ParseHeader()
		this.UnMaskPayload()

		if (this.Opcode = WSOpcodes.Text) {
			NumPut(0, this.pPayload + 0, this.PayloadSize, "UChar") 
			; Null terminate for TEXT opcodes, since stupid `StrGet()` takes a number of characters, and not a number of bytes.
			; "Ah yeah, I know loads of protocols that communicate in terms of how many UTF-8 *characters* are in a message"

			; This is safe, since `WSClient.OnRecv()` allocates `DataSize + 1` bytes (specifically for us)

			this.PayloadText := StrGet(this.pPayload, "UTF-8", this.PayloadSize)
		}
	}

	ParseHeader(){
		OpcodeAndFlags := this.ReadUChar(0)
		
		this.Final := OpcodeAndFlags & 0x80 ? True : False
		this.rsv1 := OpcodeAndFlags & 0x40 ? True : False
		this.rsv2 := OpcodeAndFlags & 0x20 ? True : False
		this.rsv3 := OpcodeAndFlags & 0x10 ? True : False
		
		this.Opcode := OpcodeAndFlags & 0xF

		MaskAndLength := this.ReadUChar(1)
		
		this.IsMasked := MaskAndLength & 0x80 ? True : False
		
		this.PayloadSize := MaskAndLength & 0x7F

		LengthSize := 0

		if (this.PayloadSize = 0x7E) {
			LengthSize := 2
			this.PayloadSize := DllCall("Ws2_32\ntohs", "UShort", this.ReadUShort(2), "UShort")
		} 
		else if (this.PayloadSize = 0x7F) {
			LengthSize := 8
			this.PayloadSize := DllCall("Ws2_32\ntohll", "UInt64", this.ReadUInt64(2), "UInt64")
		}

		this.pKey := this.pData + 2 + LengthSize ; Only actually used if we are masked, otherwise it is equal to pPayload
		this.pPayload := this.pKey + (this.IsMasked * 4)
	}

	UnMaskPayload() {
		if (!this.IsMasked) {
			Return
		}

		loop, % this.PayloadSize {
			Index := A_Index - 1

			Old := NumGet(this.pPayload + 0, Index, "UChar")
			Mask := NumGet(this.pKey + 0, Index & 3, "UChar")

			NumPut(Old ^ Mask, this.pPayload + 0, Index, "UChar")
		}
	}
}

class WSFragmentedRequest extends ReadOnlyBufferBase {
	Fragments := []
	Final := false
	PayloadSize := 0

	; Buffer that holds the data from all fragments received so far, but is only updated when it is actually used
	FullPayloadFragmentCount := 0
	FullPayloadBufferSize := 0
	FullPayloadBuffer := ""

	__New(FirstFragment) {
		this.Fragments.Push(FirstFragment)
		this.PayloadSize += FirstFragment.PayloadSize

		this.Opcode := FirstFragment.Opcode
	}

	Update(NextFragment) {
		if (this.Final) {
			Throw Exception("An additional fragment was added to a websocket request which was already complete")
		}

		this.Fragments.Push(NextFragment)
		this.PayloadSize += NextFragment.PayloadSize

		if (NextFragment.Final) {
			this.Final := true
		}

		if (NextFragment.Opcode != 0) {
			Throw Exception("The server replied with a request fragment containing a non-zero opcode")
		}
	}

	pData[] {
		get {
			; Someone wants this request's data

			if (this.FullPayloadBufferSize != this.Fragments.Count()) {
				this.SetCapacity("FullPayload", this.PayloadSize)

				pFullPayload := this.GetAddress("FullPayload")
				Offset := this.FullPayloadBufferSize

				loop, % this.Fragments.Count() - this.FullPayloadFragmentCount {
					Index := this.FullPayloadFragmentCount + A_Index - 1

					CopyFragment := this.Fragments[Index]

					MoveMemory(pFullPayload + Offset, CopyFragment.pPayload, CopyFragment.PayloadSize)

					Offset += CopyFragment.PayloadSize
				}

				this.FullPayloadBufferSize := this.PayloadSize
				this.FullPayloadFragmentCount := this.Fragments.Count()

				if (this.Opcode = WSOpcodes.Text) {
					this.PayloadText := StrGet(pFullPayload, "UTF-8", this.PayloadSize)
				}
			}

		}
	}
	
}

class WSResponse {
	__new(opcode := 0x01, pMessage := "", length := 0, fin := True){
		this.opcode := opcode
		this.fin := fin
		this.pMessage := pMessage
		this.length := length
	}
	
	encode() {
		byte1 := (this.fin? 0x80 : 0x00) | this.opcode
		
		if(this.length < 127) {
			byteArr := [byte1, this.length]
		
		} else if(this.length <= 65535) {
			lengthBytes := Uint16ToUChar(this.length)
			byteArr := [byte1, 0x7E, lengthBytes[1], lengthBytes[2]]
		
		} else if(this.length < 2 ^ 53) {
			lengthBytes := Uint64ToUChar(this.length)
			byteArr := [byte1, 0x7F, lengthBytes[1], lengthBytes[2], lengthBytes[3], lengthBytes[4]]
			
		}
		
		byteArr[2] |= 0x80 ; Set MASK bit

		length := this.length + byteArr.Length() + 4
		buf := new Buffer(length)

		VarSetCapacity(result, byteArr.Length())
		for i, byte in byteArr {
			NumPut(byte, result, A_Index - 1, "UInt")
		}
		buf.Write(&result, byteArr.Length())

		VarSetCapacity(TempMask, 4, 0)
		NumPut(TempMask, 0, "UInt")

		buf.Write(&TempMask, 4)
		buf.Write(this.pMessage, this.length)

		return buf
	}
	
}

#Include %A_LineFile%\..\Buffer.ahk