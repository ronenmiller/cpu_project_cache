//import Types::*;
import ProjectTypes::*;
import ProcTypes::*;
//import MemTypes::*;
import RFile::*;
import IMemory::*;
//import DMemory::*;
import Decode::*;
import Exec::*;
import Cop::*;
import Vector::*;
import FIFOF::*;

typedef enum {SendReq,WBSt,WBLd} CopState deriving (Bits, Eq);

interface Proc;
   method ActionValue#(Tuple2#(RIndx, Data)) cpuToHost;
   method Action hostToCpu(Bit#(32) startpc);
   //interface with L1 (Memory)
	method ActionValue#(CPUToL1CacheReq) cpuReqCache; 
	method Action cacheRespCPU(Data r); 
endinterface

(* synthesize *)
module [Module] mkProc(Proc);
  Reg#(Addr) pc     <- mkRegU;
  RFile      rf     <- mkRFile;
  IMemory  iMem   <- mkIMemory;
  //DMemory  dMem   <- mkDMemory;
  Cop        cop    <- mkCop;
  Reg#(ExecInst) eInstReg     <- mkRegU;
  Reg#(CopState) state     <- mkReg(SendReq);
  
  // fifo for working with memory
  FIFOF#(CPUToL1CacheReq)  cpuReqQ   <- mkFIFOF();
  FIFOF#(Data)  cpuRespQ             <- mkFIFOF();
  
  rule printPC;
  	$display("PROC> PC is %h",pc);
  endrule
  
  rule doProcSendReq(cop.started && state == SendReq);
	//request for instruction
	$display("IN DO_PROC>");
    let inst = iMem.req(pc);
    $display("OneCyc> received IMemResp %h",inst);
    
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
	CPUToL1CacheReq cpuReq;
	cpuReq.op = (eInst.iType == Ld) ? Rd : Wr;
	cpuReq.addr = eInst.addr;
	//cpuReq.data = (eInst.iType == Ld) ? (?) : eInst.data;
	
    if(eInst.iType == Ld)
    begin
      cpuReq.data = ?;
  	  cpuReqQ.enq(cpuReq);
  	  state <= WBLd;
    end
    else if(eInst.iType == St)
    begin
      match {.byteEn, .data} = scatterStore(eInst.addr, eInst.byteEn, eInst.data);
      cpuReq.data = data;
   	  cpuReqQ.enq(cpuReq);
  	  state <= WBSt;
    end
    else begin
    	if(isValid(eInst.dst) && validValue(eInst.dst).regType == Normal)
    		rf.wr(validRegValue(eInst.dst), eInst.data);

	    // update the pc depending on whether the branch is taken or not
	    pc <= eInst.brTaken ? eInst.addr : pc + 4;

    	// Co-processor write for debugging and stats
   	 	cop.wr(eInst.dst, eInst.data);
   	 end
    eInstReg <= eInst;
  endrule
	// if st just perform
	rule wbSt(cop.started && state == WBSt);
		ExecInst eInst = eInstReg;
		// write back
	    if(isValid(eInst.dst) && validValue(eInst.dst).regType == Normal)
    		rf.wr(validRegValue(eInst.dst), eInst.data);

	    // update the pc depending on whether the branch is taken or not
	    pc <= eInst.brTaken ? eInst.addr : pc + 4;

    	// Co-processor write for debugging and stats
   	 	cop.wr(eInst.dst, eInst.data);
   	 	state <= SendReq;
   	endrule
   	
   	/// if Ld wait for val and then perform
   	rule wbLd(cop.started && state == WBLd);
		ExecInst eInst = eInstReg;
   		$display("OneCyc> inside getResp");
		let data = cpuRespQ.first;
		cpuRespQ.deq;
        eInst.data = gatherLoad(eInst.addr, eInst.byteEn, eInst.unsignedLd, data);
		// write back
	    if(isValid(eInst.dst) && validValue(eInst.dst).regType == Normal)
    		rf.wr(validRegValue(eInst.dst), eInst.data);

	    // update the pc depending on whether the branch is taken or not
	    pc <= eInst.brTaken ? eInst.addr : pc + 4;

    	// Co-processor write for debugging and stats
   	 	cop.wr(eInst.dst, eInst.data);
	    state <= SendReq;
   	endrule
	
  
	method ActionValue#(Tuple2#(RIndx, Data)) cpuToHost;
		let ret <- cop.cpuToHost;
		$display("sending %d %d", tpl_1(ret), tpl_2(ret));
		return ret;
	endmethod

	method Action hostToCpu(Bit#(32) startpc) if (!cop.started);
		cop.start;
		$display("CPU starting");
		pc <= startpc;
	endmethod


	method ActionValue#(CPUToL1CacheReq) cpuReqCache;
		cpuReqQ.deq;
		return cpuReqQ.first;
	endmethod
	
	method Action cacheRespCPU(Data r);
		cpuRespQ.enq(r);
	endmethod
	
endmodule
