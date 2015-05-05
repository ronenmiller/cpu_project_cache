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
	
	// for processor simulation
	Cop       cop <- mkCop;
	RFile      rf <- mkRFile;
	Memory 	mem <- mkProjMemory;
	
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
	
	// push l1 request
	rule pushReq0(state==Run && cycle ==1);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'b1101;
		r.data = ?;
		$display("Sending request to cache for address: 0x%h",r.addr);
		cache.cacheProcIF[0].req(r);
		let response <- cache.cacheProcIF[0].resp;
		$display("Got response from cache: 0x%h",response);
	endrule
	
	// get mem req from l2
	rule getMemReq(state == Run && isMemReq == 0);
		MemReq r <- cache.mReqDeq;
		mem.req(r);
		if (r.op == Ld) begin
			isMemReq <= 1;
		end
	endrule
	
	// send mem response to l2
	rule memResp(state == Run && isMemReq != 0);
		MemResp resp <- mem.resp;
		$display("TB> sending mem response with data 0x%h",resp);
		cache.memResp(resp);
		isMemReq <= 0;
	endrule
	
	// start simulation
	rule start(state == Start);
		state <= Run;
		cop.start;
		pc <= startpc;
	endrule
	
	// check if finished
	rule checkFinished(state == Run);
		let c <- cop.cpuToHost;
		$display("Received from cpu %d %d", tpl_1(c), tpl_2(c));
		$display("\n--------------------------------------------\n");
		if(tpl_1(c) == 21)
		begin
		if (tpl_2(c) == 0)
		begin
			$display("PASSED\n");
			end
		else
		begin
				$display("FAILED %d\n", c);
		end
		$finish;
		end
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
