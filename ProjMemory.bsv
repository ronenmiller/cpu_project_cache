/*

Copyright (C) 2012 Muralidaran Vijayaraghavan <vmurali@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

import ProjectTypes::*;
import RegFile::*;
import Fifo::*;
import Vector::*;

interface Memory;
  method Action req(MemReq r);
  method ActionValue#(MemResp) resp;
endinterface

(* synthesize *)
module mkProjMemory(Memory);
  RegFile#(Bit#(26), BlockData) mem <- mkRegFileWCFLoad("memory.vmh", 0, maxBound);

  Fifo#(2, MemReq) dMemReqQ <- mkCFFifo;
  Fifo#(2, MemResp) dMemRespQ <- mkCFFifo;

  rule getDResp;
    let req = dMemReqQ.first;
    let idx = truncate(req.addr >> OffsetSz);
    let data = mem.sub(idx);
    if(req.op==St)
    begin
      Vector#(NumBytes, Bit#(8)) bytesIn = unpack(req.data);
      mem.upd(idx, pack(bytesIn));
    end
    else
      dMemRespQ.enq(data);
    dMemReqQ.deq;
  endrule

  method req = dMemReqQ.enq;

  method ActionValue#(MemResp) resp;
    dMemRespQ.deq;
    return dMemRespQ.first;
  endmethod

endmodule

