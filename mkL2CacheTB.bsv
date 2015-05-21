import mkL2Cache::*;
import ProjectTypes::*;
import Randomizable :: * ;
import Vector::*;
import FIFOF::*;
import FIFO::*;
import Fifo::*;
import SpecialFIFOs::*;

typedef enum {Start, Run, Finish} TBState deriving (Bits, Eq);
typedef 2 NumCPU2;
typedef 3 NumCPU3;
typedef CacheReq#(NumCPU3) CacheReq3;

(* synthesize *)
module mkL2CacheTB();
	Reg#(TBState) state <- mkReg(Start);
	Reg#(Bit#(1)) finish <- mkReg(0);
	Reg#(Bit#(10)) cycle <- mkReg(0);
	L2Cache#(NumCPU3) l2Cache <- mkL2Cache();
	Reg#(Bit#(10)) numReq <- mkReg(0);
	Randomize#(MemResp) randDataMem <- mkGenericRandomizer;
	Randomize#(BlockData) randDataCache <- mkGenericRandomizer;
	Randomize#(Addr) randAddr <- mkGenericRandomizer;
	Reg#(Bit#(1)) isMemReq <- mkReg(0);
	Reg#(Bit#(1)) isInv <- mkReg(0);
	Reg#(Bool) initialized <- mkReg(False);
	Reg#(Bool) l2Ready <- mkReg(True);
	Reg#(Addr) prevAddr <- mkReg(0);
	Reg#(Addr) addr <- mkReg(0);
	Reg#(Bit#(3)) proc <- mkReg(001);
	Reg#(Bool) isWB <- mkReg(False);
	Fifo#(40,Addr) addrBank <- mkCFFifo;
	
	// start of TB	
	rule checkStart(state == Start);
		state <= Run;
		let a <- randAddr.next;
		addr <= a;
		addrBank.enq(a);
	endrule	

	// initialize randomizers
	rule init (!initialized);
	    randDataMem.cntrl.init(); 
	    randAddr.cntrl.init();
	    randDataCache.cntrl.init();
	    initialized <= True; 
	endrule
	 
	// get mem request from l2
	rule getMemReq(state == Run && isMemReq == 0);
		MemReq r <- l2Cache.mReqDeq;
		IndexL2 idx =	truncate(r.addr>>valueOf(OffsetSz));
		TagL2 tag = truncateLSB(r.addr);
		$display("TB> got mem request of type %b for address 0x%h index is %4d tag is 0x%h",r.op,r.addr, idx,tag);
		if (r.op == Ld) begin
			isMemReq <= 1;
		end
	endrule
	
	// send mem response to l2
	rule memResp(state == Run && isMemReq != 0);
		MemResp resp <- randDataMem.next;
		$display("TB> sending mem response with data 0x%h",resp);
		l2Cache.memResp(resp);
		isMemReq <= 0;
	endrule
	
	// deq l2 to l1 response
	rule deqResp(state == Run && !isWB);
		let resp = l2Cache.resp;
		l2Cache.respDeq;
		$display("TB> Response from l2 to l1 is: 0x%h",resp);
		numReq <= numReq+1;
		let a <- randAddr.next;
		addr <= a;
		$display("numreq is: %d",numReq);
		if (numReq >= 34) begin
			isWB <= True;
		end
	endrule
	
	// deq inv response
	rule deqInv(isInv == 0);
		let invReq <- l2Cache.cacheInvDeq;
		TagL2 tag = truncateLSB(invReq.addr);
		$display("TB> Got Inv - InvVec: %b , Type: %b, addr: 0x%h tag is: 0x%h",invReq.proc, invReq.reqType,invReq.addr,tag);
		isInv <= 1;
	endrule
	
	//send modified after invalidation or get modified request
	rule sendModified(isInv==1);
		let a <- randDataCache.next();
		l2Cache.cacheModifiedResp(a);
		isInv <= 0;
	endrule
	
	
	/*****************************************
		Start of test 1
	*****************************************/
	// randomize addresses and request Rd for Rows*Ways +3 times - insures replacements
	rule sendReq0(state == Run && cycle > 2 && numReq <= 12);
		let blockStats = l2Cache.getDirStats(addr);
		$display("TB> For address 0x%h got State: %b and Present: %b",addr,blockStats.state,blockStats.present);
		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = proc;
		IndexL2 idx =	truncate(cReq.addr>>valueOf(OffsetSz));
		TagL2 tag = truncateLSB(cReq.addr);
		$display("TB> Sending l1 to l2 Rd request from proc %b for address 0x%h index is %4d tag is 0x%h",proc, addr,idx,tag);
		l2Cache.req(cReq);
		if (proc < 3'b100) proc <= (proc*2);
		else proc <= 3'b001;
	endrule
	
	// randomize addresses and request Rd and save addresses
	rule sendReq1(state == Run && cycle > 2 && numReq > 12 && numReq <= 20);
		let blockStats = l2Cache.getDirStats(addr);
		$display("TB> For address 0x%h got State: %b and Present: %b",addr,blockStats.state,blockStats.present);
		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = proc;
		IndexL2 idx =	truncate(cReq.addr>>valueOf(OffsetSz));
		TagL2 tag = truncateLSB(cReq.addr);
		$display("TB> Sending l1 to l2 Rd request from proc %b for address 0x%h index is %4d tag is 0x%h",proc, addr,idx,tag);
		l2Cache.req(cReq);
		addrBank.enq(addr);
		if (proc < 3'b100) proc <= (proc*2);
		else proc <= 3'b001;
	endrule
	
	
	// get addresses from bank and request Rd for All addresses to get some hits
	rule sendReq2(state == Run && numReq > 20 && numReq <= 26);
		let blockStats = l2Cache.getDirStats(addr);
		$display("TB> For address 0x%h got State: %b and Present: %b",addr,blockStats.state,blockStats.present);
		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addrBank.first;
		cReq.data = ?;
		cReq.proc = proc;
		IndexL2 idx =	truncate(cReq.addr>>valueOf(OffsetSz));
		TagL2 tag = truncateLSB(cReq.addr);
		$display("TB> Sending l1 to l2 Rd request from proc %b for address 0x%h index is %4d tag is 0x%h",proc, addr,idx,tag);
		l2Cache.req(cReq);
		addrBank.deq;
		addrBank.enq(cReq.addr);
		if (proc < 3'b100) proc <= (proc*2);
		else proc <= 3'b100;
	endrule
	
	
	// get addresses from bank and request Wr for All addresses to get some hits and Invalidates...
	rule sendReq3(state == Run && numReq > 26 && numReq <= 34 && addrBank.notEmpty);
		let blockStats = l2Cache.getDirStats(addr);
		CacheReq3 cReq;
		cReq.op = Wr;
		cReq.addr = addrBank.first;
		cReq.data = ?;
		
		IndexL2 idx =	truncate(cReq.addr>>valueOf(OffsetSz));
		TagL2 tag = truncateLSB(cReq.addr);
		addrBank.deq;
		// save only some wr addresses to later perform WB
		if (numReq >= 32) begin
			addrBank.enq(cReq.addr);
			cReq.proc = 3'b010;
		end
		else begin
			cReq.proc = proc;
			if (proc < 3'b100) begin
				proc <= (proc*2);
			end
			else proc <= 3'b100;
		end
		$display("TB> Sending l1 to l2 Wr request from proc %b for address 0x%h index is %4d tag is 0x%h",cReq.proc, addr,idx,tag);
		l2Cache.req(cReq);
	endrule
	
	
	// get addresses from bank and request WB from l1 to l2 for some modified addresses
	rule sendReq4(state == Run && numReq > 34 && addrBank.notEmpty && isWB);
		let blockStats = l2Cache.getDirStats(addr);
		$display("TB> For address 0x%h got State: %b and Present: %b",addr,blockStats.state,blockStats.present);
		CacheReq3 cReq;
		cReq.op = WB;
		cReq.addr = addrBank.first;
		cReq.data = ?;
		cReq.proc = 3'b010;
		IndexL2 idx =	truncate(cReq.addr>>valueOf(OffsetSz));
		TagL2 tag = truncateLSB(cReq.addr);
		$display("TB> Sending l1 to l2 WB request from proc %b for address 0x%h index is %4d tag is 0x%h",cReq.proc, addr,idx,tag);
		l2Cache.req(cReq);
		addrBank.deq;
	endrule
	/*****************************************
		End of test 1
	*****************************************/
	
	// count cycles
	rule countcyc(state == Run);
		cycle <= cycle+1;
		$display("Cycle: %d",cycle);
		if (cycle == 250) begin
			state <= Finish;
		end
	endrule
	
	// finish the test
  	rule checkFinished(state == Finish);
		$display("Finish");
		$finish;
  	endrule
endmodule

