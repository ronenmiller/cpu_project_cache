import onecyc::*;
import ProjectTypes::*;
import ProjMemory::*;
import mkProject::*;

typedef 4 NumCPU; 
typedef enum {Start, Run, Finish} State deriving (Bits, Eq);

(* synthesize *)
module mkTestBench();
	Reg#(Bit#(32))                 cycle       <- mkReg(0);
	Reg#(State)                    state       <- mkReg(Start);
	Vector#(NumCPU, Reg#(Bit#(1))) isCacheReq  <- mkReg(0);
	Reg#(Bit#(1))                  isMemReq    <- mkReg(0);

	CacheProj#(NumCPU)    cache  <- mkProject;
	Memory                memory <- mkProjMemory;
	Vector#(NumCPU, Proc) cpuVec <- mkProc;
 
	rule start(state == Start);
		proc.hostToCpu(32'h1000);
		state <= Run;
	endrule
  
	// get request from cpu and send to l1
	for (Integer i=0; i < valueOf(NumCPU); i = i+1)
	begin
		rule sendCPUReq(state == Run && isCacheReq[i] == 0);
			let r <- cpuVec[i].cpuReqCache;
			$display("TB> got cpu request of type %b for address 0x%h", r.op, r.addr);
			cache.cacheProcIF0[i].req(r);
			isCacheReq[i] <= 1;
		endrule
	end
	
	// get l1 response and send to cpu
	for (Integer i=0; i < valueOf(NumCPU); i = i+1)
	begin
		rule getCacheResp(state == Run && isCacheReq[i] == 1);
			let r <- cache.cacheProcIF0[i].resp;
			display("TB> sending cache response with data 0x%h", r);
			cpuVec[i].cacheRespCPU(r);
			isCacheReq[i] <= 0;
		endrule
	end
  
	// get request from l2 and send to memory
	rule getMemReq(state == Run && isMemReq == 0);
		MemReq r <- cache.mReqDeq;
		$display("TB> got mem request of type %b for address 0x%h",r.op ,r.addr);
		memory.req(r);
		isMemReq <= 1;
	endrule
	
	// get memory response and send to l2
	rule memResp(state == Run && isMemReq == 1);
		MemResp resp <- memory.resp;
		$display("TB> sending mem response with data 0x%h",resp);
		cache.memResp(resp);
		isMemReq <= 0;
	endrule
  
    //rule countCyc - count the number of cycles
	rule countCyc(state == Run);
		cycle <= cycle+1;
		$display("\n##Cycle: %d##",cycle);
		if (cycle == 10) begin
			state <= Finish;
		end
	endrule
	
  // rule run(state == Run);
    // cycle <= cycle + 1;
    // $display("\ncycle %d", cycle);
  // endrule

	rule checkFinished(state == Run);
		let c <- proc.cpuToHost;
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
 
endmodule

