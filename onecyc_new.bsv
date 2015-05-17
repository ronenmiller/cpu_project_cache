
import Types::*;
import ProcTypes::*;
//import MemTypes::*;
import RFile::*;
//import IMemory::*;
//import DMemory::*;
import Decode::*;
import Exec::*;
import Cop::*;
import Vector::*;


interface Proc;
   method ActionValue#(Tuple2#(RIndx, Data)) cpuToHost;
   method Action hostToCpu(Bit#(32) startpc);
endinterface

(* synthesize *)
module [Module] mkProc(Proc);
  Reg#(Addr) pc     <- mkRegU;
  RFile      rf     <- mkRFile;
  //IMemory  iMem   <- mkIMemory;
  //DMemory  dMem   <- mkDMemory;
  Cop        cop    <- mkCop;
  
  // fifo for working with memory
  FIFOF#(MemReq)  cpuReqQ  <- mkFIFOF();
  FIFOF#(MemResp)  cpuRespQ <- mkFIFOF();
  
  rule doProc(cop.started);
	MemReq req;
	MemResp resp;
	req.op = Ld;
    req.byteEn = ?;
    req.addr = pc;
    req.data = ?;
	
	cpuReqQ.enq(req);
	resp = cpuRespQ.first;
	cpuRespQ.deq;
    //let inst = iMem.req(pc);
    
    // decode
    let dInst = decode(inst);

    // trace - print the instruction
    $display("pc: %h inst: (%h) expanded: ", pc, inst, showInst(inst));

    // read register values 
    let rVal1 = rf.rd1(validRegValue(dInst.src1));
    let rVal2 = rf.rd2(validRegValue(dInst.src2));     

    // Co-processor read for debugging
    let copVal = cop.rd(validRegValue(dInst.src1));

    // execute
    let eInst = exec(dInst, rVal1, rVal2, pc, ?, copVal);  // The fifth argument is the predicted pc, to detect if it was mispredicted. Since there is no branch prediction, this field is sent with a random value

    // Executing unsupported instruction. Exiting
    if(eInst.iType == Unsupported)
    begin
      $fwrite(stderr, "Executing unsupported instruction at pc: %x. Exiting\n", pc);
      $finish;
    end

    // memory
    if(eInst.iType == Ld)
    begin
      let data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, byteEn: ?, data: ?});
      eInst.data = gatherLoad(eInst.addr, eInst.byteEn, eInst.unsignedLd, data);
    end
    else if(eInst.iType == St)
    begin
      match {.byteEn, .data} = scatterStore(eInst.addr, eInst.byteEn, eInst.data);
      let d <- dMem.req(MemReq{op: St, addr: eInst.addr, byteEn: byteEn, data: data});
    end

    // write back
    if(isValid(eInst.dst) && validValue(eInst.dst).regType == Normal)
      rf.wr(validRegValue(eInst.dst), eInst.data);

    // update the pc depending on whether the branch is taken or not
    pc <= eInst.brTaken ? eInst.addr : pc + 4;

    // Co-processor write for debugging and stats
    cop.wr(eInst.dst, eInst.data);
  endrule
  
  
  method ActionValue#(Tuple2#(RIndx, Data)) cpuToHost;
    let ret <- cop.cpuToHost;
    $display("sending %d %d", tpl_1(ret), tpl_2(ret));
    return ret;
  endmethod

  method Action hostToCpu(Bit#(32) startpc) if (!cop.started);
    cop.start;
    pc <= startpc;
  endmethod
endmodule
