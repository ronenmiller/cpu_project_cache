import mkL2Cache::*;
import ProjectTypes::*;
import Randomizable :: * ;

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
	Randomize#(BlockData) randData <- mkGenericRandomizer;
	Randomize#(Addr) randAddr <- mkGenericRandomizer;
	Reg#(Bit#(1)) isMemReq <- mkReg(0);
	Reg#(Bool) initialized <- mkReg(False);
	Reg#(Bool) l2Ready <- mkReg(True);
	Reg#(Addr) prevAddr <- mkReg(0);
	Reg#(Addr) addr <- mkReg(0);
	
	/*
	function Integer pushReq(Bit#(NumCPU3) proc, CacheOp op, BlockData data, Addr addr, Bit#(numCPU) present, Integer misses, Integer hits, Bool checkPrev);
		CacheReq3 cReq;
		cReq.op = op;
		cReq.addr = addr;
		cReq.data = data;
		cReq.proc = proc;
		
		if(checkPrev) begin
			let miss = l2Cache.getMiss;
			let hit = l2Cache.getHit;
			let blockStats = l2Cache.getDirStats(prevAddr);
			$display("TB> For address 0x%h got State: %b and Present: %b",prevAddr,blockStats.state,blockStats.present);
			if (miss != 1 || hit != 0 || blockStats.state != Shared || blockStats.present != present) begin
				$display("TB> Error: hit miss values mismatch after request 0");
				$finish;
			end
		end
		action;
			l2Cache.req(cReq);
		endaction
		
	endfunction
	*/
		
	rule checkStart(state == Start);
		state <= Run;
		let a <- randAddr.next;
		addr <= a;
	endrule	

	rule init (!initialized);
	    randData.cntrl.init(); 
	    randAddr.cntrl.init();
	    initialized <= True; 
	endrule
	 
	// get mem request from l2
	rule getMemReq(state == Run && isMemReq == 0);
		MemReq r <- l2Cache.mReqDeq;
		Index idx =	truncate(r.addr>>valueOf(OffsetSz));
		Tag tag = truncateLSB(r.addr);
		$display("TB> got mem request for address 0x%h index is %4d ",r.addr, idx);
		isMemReq <= 1;
		MemResp resp <- randData.next;
		
	endrule
	
	// send mem response to l2
	rule memResp(state == Run && isMemReq != 0);
		MemResp resp <- randData.next;
		$display("TB> sending mem response with data 0x%h",resp);
		l2Cache.memResp(resp);
		isMemReq <= 0;
	endrule
	
	// deq l2 to l1 response
	rule deqResp(state == Run);
		let resp = l2Cache.resp;
		l2Cache.respDeq;
		$display("TB> Response from l2 to l1 is: 0x%h",resp);
		numReq <= numReq+1;
		let a <- randAddr.next;
		addr <= a;
	endrule
	
	
	
	/*****************************************
		Start of test 1
	*****************************************/
	
	rule sendReq0(state == Run && cycle > 2);//&& numReq == 0 && cycle > 2);
		//pushReq(3'b010, Rd, 0, addr, 0, 0, False);
		let miss = l2Cache.getMiss;
		let hit = l2Cache.getHit;
		let blockStats = l2Cache.getDirStats(prevAddr);

		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = 3'b010;
		l2Cache.req(cReq);
		$display("TB> Sending l1 to l2 Rd request to address 0x%h", addr);
	endrule
	//TODO: add fifo to use previous addresses by different cpu's.
	/*
	rule sendReq1(state == Run && numReq == 1 );
		//pushReq(3'b010, Rd, 0, addr, 0, 0, False);
		let miss = l2Cache.getMiss;
		let hit = l2Cache.getHit;
		let blockStats = l2Cache.getDirStats(prevAddr);

		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = 3'b010;
		l2Cache.req(cReq);
		$display("TB> Sending l1 to l2 Rd request to address 0x%h", addr);
	endrule
	
	rule sendReq2(state == Run && numReq == 2 );
		//pushReq(3'b010, Rd, 0, addr, 0, 0, False);
		let miss = l2Cache.getMiss;
		let hit = l2Cache.getHit;
		let blockStats = l2Cache.getDirStats(prevAddr);

		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = 3'b010;
		l2Cache.req(cReq);
		$display("TB> Sending l1 to l2 Rd request to address 0x%h", addr);
	endrule
	
	rule sendReq3(state == Run && numReq == 3 );
		//pushReq(3'b010, Rd, 0, addr, 0, 0, False);
		let miss = l2Cache.getMiss;
		let hit = l2Cache.getHit;
		let blockStats = l2Cache.getDirStats(prevAddr);

		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = 3'b010;
		l2Cache.req(cReq);
		$display("TB> Sending l1 to l2 Rd request to address 0x%h", addr);
	endrule
	
	rule sendReq4(state == Run && numReq == 4 );
		//pushReq(3'b010, Rd, 0, addr, 0, 0, False);
		let miss = l2Cache.getMiss;
		let hit = l2Cache.getHit;
		let blockStats = l2Cache.getDirStats(prevAddr);

		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = 3'b010;
		l2Cache.req(cReq);
		$display("TB> Sending l1 to l2 Rd request to address 0x%h", addr);
	endrule
	
	rule sendReq5(state == Run && numReq == 5 );
		//pushReq(3'b010, Rd, 0, addr, 0, 0, False);
		let miss = l2Cache.getMiss;
		let hit = l2Cache.getHit;
		let blockStats = l2Cache.getDirStats(prevAddr);

		CacheReq3 cReq;
		cReq.op = Rd;
		cReq.addr = addr;
		cReq.data = ?;
		cReq.proc = 3'b010;
		l2Cache.req(cReq);
		$display("TB> Sending l1 to l2 Rd request to address 0x%h", addr);
	endrule
	*/
	/*****************************************
		End of test 1
	*****************************************/
	
	rule countcyc(state == Run);
		cycle <= cycle+1;
		$display("Cycle: %d",cycle);
		
		if (cycle == 500) begin
			state <= Finish;
		end
	endrule
	
  	rule checkFinished(state == Finish);
		$display("Finish");
		$finish;
  	endrule
endmodule

