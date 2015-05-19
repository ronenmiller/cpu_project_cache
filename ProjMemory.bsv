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

