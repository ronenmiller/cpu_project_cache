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
  //RegFile#(Bit#(27), BlockData) mem <- mkRegFileWCFLoad("memory.vmh", 0, maxBound);
  RegFile#(Bit#(23), BlockData) mem <- mkRegFileWCF(0, maxBound);
  Fifo#(2, MemReq) dMemReqQ <- mkCFFifo;
  Fifo#(2, MemResp) dMemRespQ <- mkCFFifo;

  rule getDResp;
    let req = dMemReqQ.first;
    Bit#(23) index = truncate(req.addr>>6);
    let idx = truncate(req.addr >> valueOf(OffsetSz));
    let data = mem.sub(idx);
    if(req.op==St)
    begin
      mem.upd(idx,data);
    end
    else
      dMemRespQ.enq(data);
    dMemReqQ.deq;
  endrule

  //method req = dMemReqQ.enq;
	method Action req(MemReq r);
		dMemReqQ.enq(r);
	endmethod
	
  method ActionValue#(MemResp) resp;
    dMemRespQ.deq;
    return dMemRespQ.first;
  endmethod

endmodule

