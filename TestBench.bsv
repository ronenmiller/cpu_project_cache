import oneCyc::*;
import ProjectTypes::*;
import ProjMemory::*;
import mkProject::*;
import Vector::*;

typedef 4 NumCPU; 
typedef enum {Start, Run, Finish} State deriving (Bits, Eq);

(* synthesize *)
module mkTestBench();
	Reg#(Bit#(32))                 cycle       <- mkReg(0);
	Reg#(State)                    state       <- mkReg(Start);

	CacheProj#(NumCPU)    		cache  				<- mkProject;
	Memory                		memory 				<- mkProjMemory;
	Proc				  		proc	 			<-mkProc;
	Reg#(Bit#(TLog#(NumCPU)))	nextL1				<- mkReg(0);
	Reg#(Bool)					sendReq				<- mkReg(True);	
	Reg#(Bool)					isWr				<- mkReg(False);
	
	rule printState;
		$display("TB>state is: %h",state);
	endrule
	
	rule start(state == Start);
		state <= Run;
	endrule
	  
 	// start program in CPU
	rule init(state == Start);
		proc.hostToCpu(32'h1000);
	endrule
	
	// get request from cpu and send to l1
	rule sendCPUReq(state == Run && sendReq);
		let r <- proc.cpuReqCache;
		$display("TB> got cpu request of type %b for address 0x%h", r.op, r.addr);
		cache.cacheProcIF[nextL1].req(r);
		sendReq <= False;
		isWr <= (r.op == Wr);
	endrule
	
	// get l1 response and send to cpu (in case of load)
	rule getCacheRespRd(state == Run && !sendReq && !isWr);
		let r <- cache.cacheProcIF[nextL1].resp;
		$display("TB> sending cache response with data 0x%h", r);
		proc.cacheRespCPU(r);
		nextL1 <= nextL1+1;
		sendReq <= True;
	endrule
	
	// get l1 response and send to cpu (for Store no need to wait for response)
	rule getCacheRespWr(state == Run && !sendReq && isWr);
		$display("TB> Finished Wr");
		nextL1 <= nextL1+1;
		sendReq <= True;
	endrule
	
	// check if simulation finished
	rule checkFinished(state == Run);
		let c <- proc.cpuToHost;
		$display("\n--------------------------------------------\n");
		if(tpl_1(c) == 21)
		begin
			if (tpl_2(c) == 0)
			begin
				$display("PASSED");
				$finish;
			end
			else
			begin
				$display("FAILED val %d\n", c);
			end
		end
	endrule
	
	
  
	// get request from l2 and send to memory
	rule getMemReq(state == Run);
		MemReq r <- cache.mReqDeq;
		$display("TB> got mem request of type %b for address 0x%h",r.op ,r.addr);
		memory.req(r);
	endrule
	
	// get memory response and send to l2
	rule memResp(state == Run);
		MemResp resp <- memory.resp;
		$display("TB> sending mem response with data 0x%h",resp);
		cache.memResp(resp);
	endrule
  
    //rule countCyc - count the number of cycles
	rule countCyc(state == Run);
		cycle <= cycle+1;
		$display("\n##Cycle: %d##",cycle);
		if (cycle == 1500) begin
			state <= Finish;
			$finish;
		end
	endrule
	

	
 
endmodule

