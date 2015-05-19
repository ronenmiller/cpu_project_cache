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
   //interface with L1 (Memory)
   	method ActionValue#(CPUToL1CacheReq) cpuReqL1; 
	method Action l1respCPU(Data r); 
endinterface

(* synthesize *)
module [Module] mkProc(Proc);
  Reg#(Addr) pc     <- mkRegU;
  RFile      rf     <- mkRFile;
  //IMemory  iMem   <- mkIMemory;
  //DMemory  dMem   <- mkDMemory;
  Cop        cop    <- mkCop;
  
  // fifo for working with memory
  FIFOF#(CPUToL1CacheReq)  cpuReqQ   <- mkFIFOF();
  FIFOF#(Data)  cpuRespQ             <- mkFIFOF();
  
  rule doProc(cop.started);
	//request for instruction
	CPUToL1CacheReq reqI;
	reqI.op = Rd;
    reqI.addr = pc;
    reqI.data = ?;
	cpuReqQ.enq(reqI);
	//get response from L1
	let inst = cpuRespQ.first;
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
		//request for data
		CPUToL1CacheReq reqLd;
		reqLd.op = Rd;
		reqLd.addr = eInst.addr;
		reqLd.data = ?;
		cpuReqQ.enq(reqLd);
		//get response from L1
		let data = cpuRespQ.first;
		cpuRespQ.deq;
	
		//let data <- dMem.req(MemReq{op: Ld, addr: eInst.addr, byteEn: ?, data: ?});
		eInst.data = gatherLoad(eInst.addr, eInst.byteEn, eInst.unsignedLd, data);
    end
    else if(eInst.iType == St)
    begin
		match {.byteEn, .data} = scatterStore(eInst.addr, eInst.byteEn, eInst.data);
		//request for data
		CPUToL1CacheReq reqSt;
		reqSt.op = Wr;
		reqSt.addr = eInst.addr;
		reqSt.data = data;
		cpuReqQ.enq(reqSt);
		
		//no response from L1 for St operation
		
		//let d <- dMem.req(MemReq{op: St, addr: eInst.addr, byteEn: byteEn, data: data});
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

	method ActionValue#(CPUToL1CacheReq) cpuReqL1;
		cpuReqQ.deq;
		return cpuReqQ.first;
	endmethod
	
	method Action l1respCPU(Data r);
		cpuRespQ.enq(r);
	endmethod