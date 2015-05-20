import mkProject::*;
import ProjectTypes::*;
import Randomizable :: * ;

typedef 4 NumCPU; 
typedef enum {Start, Run, Finish, Print} State deriving (Bits, Eq);

(* synthesize *)
module mkProjectTB();
	Reg#(State) state <- mkReg(Start);
	Reg#(Bit#(32)) cycle <- mkReg(0);
	Reg#(Bit#(1)) isMemReq <- mkReg(0);
	Reg#(Bool) initialized <- mkReg(False);
	
	CacheProj#(NumCPU) cache <- mkProject;
	
	//rands
	Randomize#(MemResp) randDataMem <- mkGenericRandomizer;
	Randomize#(BlockData) randDataCache <- mkGenericRandomizer;
	Randomize#(Addr) randAddr <- mkGenericRandomizer;
	
	// initialize randomizers
	rule init (!initialized);
	    randDataMem.cntrl.init(); 
	    randAddr.cntrl.init();
	    randDataCache.cntrl.init();
	    initialized <= True; 
	endrule
	
	//rule checkStart
	rule checkStart(state == Start);
		state <= Run;
	endrule

	/************************************
	Test case 1:
		- send Rd req for same address and repeat.
	*************************************/
	// push l1 0,3 requests
	rule pushReq0(state==Run && cycle < 13);
		CPUToL1CacheReq r;
		r.op = Rd;
		r.addr = 32'b11111011011101100;
		r.data = ?;
		$display("Sending Rd request to caches 0 and 3 for same address: 0x%h",r.addr);
		cache.cacheProcIF[0].req(r);
		cache.cacheProcIF[3].req(r);
	endrule
	
	/************************************
	Test case 1:
		- send Wr req for same address
	*************************************/
	// send WR request for proc 2
	rule pushReq1(state == Run && cycle == 16);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'b11111011011101100;
		r.data = 32'h24;
		$display("Sending Wr request to cache 2 for address: 0x%h",r.addr);
		cache.cacheProcIF[2].req(r);
	endrule
	
	// send WR request for proc 2
	rule pushReq2(state == Run && cycle == 22);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'b11111011011101100;
		r.data = 32'h28;
		$display("Sending Wr request to cache 2 for address: 0x%h",r.addr);
		cache.cacheProcIF[2].req(r);
	endrule
	
	// send WR request for proc 2
	rule pushReq3(state == Run && cycle == 22);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'b11111011011101100;
		r.data = 32'h28;
		$display("Sending Wr request to cache 2 for address: 0x%h",r.addr);
		cache.cacheProcIF[2].req(r);
	endrule
	
	// send WR request for proc 1
	rule pushReq4(state == Run && cycle == 25);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'b11111011011101100;
		r.data = 32'h32;
		$display("Sending Wr request to cache 1 for address: 0x%h",r.addr);
		cache.cacheProcIF[1].req(r);
	endrule
	
	/*
	// send WR request for proc 1
	rule pushReq2(state == Run && cycle == 22);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'b11111011011101100;
		r.data = 32'h24;
		$display("Sending Wr request to cache 1 for address: 0x%h",r.addr);
		cache.cacheProcIF[1].req(r);
	endrule
	*/
	/*
	// push l1[0:1] requests
	rule pushReq0(state==Run && cycle = 16);
		CPUToL1CacheReq r;
		r.op = Rd;
		// offset = 2, index = 2, tag = 2
		r.addr = 32'b101001000;
		r.data = 32'b1;
		$display("Sending request to cache 0 for address: 0x%h",r.addr);
		cache.cacheProcIF[2].req(r);
	endrule
	*/
	for (Integer i=0; i < valueOf(NumCPU); i = i+1) begin
		// get response from cache
		rule getCacheResp;
			let response <- cache.cacheProcIF[i].resp;
			$display("Got response from cache %h : 0x%h",i,response);
		endrule
	end
	
	// get mem req from l2
	rule getMemReq(state == Run && isMemReq == 0);
		MemReq r <- cache.mReqDeq;
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
		cache.memResp(resp);
		isMemReq <= 0;
	endrule
	
	// finish
	rule checkFinished(state == Finish);
		$display("Finish");
		$finish;
	endrule
		
	//rule countCyc - count the number of cycles
	rule countCyc(state == Run);
		cycle <= cycle+1;
		$display("##Cycle: %d##",cycle);
		if (cycle == 40) begin
			state <= Finish;
		end
	endrule

endmodule

