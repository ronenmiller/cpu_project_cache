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
	Reg#(Bit#(1)) isCacheReq <- mkReg(0);
	
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


	// push l1 request
	rule pushReq0(state==Run && isCacheReq == 0);
		CPUToL1CacheReq r;
		r.op = Rd;
		r.addr = 32'b11111011011101101;
		r.data = 32'b1;
		$display("Sending request to cache for address: 0x%h",r.addr);
		cache.cacheProcIF[0].req(r);
		isCacheReq <= 1;
	endrule
	
	// get response from cache
	rule getCacheResp (isCacheReq == 1);
		let response <- cache.cacheProcIF[0].resp;
		$display("Got response from cache: 0x%h",response);
		isCacheReq <= 0;
	endrule
		
	
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
		if (cycle == 10) begin
			state <= Finish;
		end
	endrule

endmodule
