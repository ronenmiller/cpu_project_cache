import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import mkL1Cache::*;
import mkL2Cache::*;
import ProjectTypes::*;


// interface between L1cache and processor
interface L1Cache_Proc;
	method Action req(CPUToL1CacheReq r);
	method ActionValue#(Data) resp;
endinterface


// interface for project
interface CacheProj#(numeric type numCPU);
	// interface with CPUs
	interface Vector#(numCPU, L1Cache_Proc) cacheProcIF;
	
	// interface with Memory
	method ActionValue#(MemReq) mReqDeq;
	method Action memResp(MemResp r);
endinterface

// mkProject module
module mkProject(CacheProj#(numCPU));
	
	// cpu to l1 interface vector - see fill at end of code
	Vector#(numCPU, L1Cache_Proc) cacheProcIF0;
	
	// create L1 cache
	Vector#(numCPU,L1Cache) l1CacheVec <- replicateM(mkL1Cache);
	
	// create L2 cache
	L2Cache#(numCPU) l2Cache <- mkL2Cache();
	
	// Reg
	Reg#(Bit#(2)) stepL1Req 	         	<- mkReg(0);
	Reg#(Bit#(1)) isL2Req                	<- mkReg(0);
	Reg#(Bit#(numCPU)) invGMProc         	<- mkReg(0);
	Reg#(Bit#(TLog#(numCPU))) cntReq     	<- mkReg(0);
	Reg#(Bit#(TLog#(numCPU))) procForReq 	<- mkReg(0);
	Reg#(ProjState) state					<- mkReg(Ready);

	
	// find out which L1 will send request to L2
	rule checkL1Req(state == Ready);
		Bit#(TLog#(numCPU)) cnt = cntReq;
		$display("TB> Checking for L1 to L2 request...");
		Bool flag = False;
		for(Integer i = 0 ; (i<valueof(numCPU) && flag == False) ; i=i+1)
		begin
			let isFull = l1CacheVec[cnt].ismReqQFull;
			$display("TB> Checking for L1[%h] isFull: %b",cnt,isFull);
			if(isFull == True) begin //if there is a request from the next L1 cache
				state <= SendL2Req;
				procForReq <= cnt;
				$display("TB> L1 number %d will send to L2 a request",cnt);
				flag = True; //break the for loop
				cntReq <= cnt+1; 
			end
			else begin
				cnt = cnt+1;
			end
		end
	endrule

	rule printProc(state == SendL2Req);
		$display("procForReq: %h",procForReq);
		$display("L1 state is: %h",state);
	endrule
	
	rule sendReqToL2(state == SendL2Req);
		let reqFromL1 = l1CacheVec[procForReq].l1Reql2;
		l1CacheVec[procForReq].l1Reql2Deq;
		CacheReq#(numCPU) reqToL2;
		reqToL2.op = reqFromL1.op;
		reqToL2.addr = reqFromL1.addr;
		reqToL2.data = reqFromL1.bData;
		reqToL2.proc = (1<<procForReq);
		l2Cache.req(reqToL2);
		$display("TB> sending L2 req");
		state <= WaitL2Resp;
	endrule
	
	// L2 sends response to L1, L1 receives response from L2 
	rule l2SendRespL1(state == WaitL2Resp);
		let resp <- l2Cache.resp;
		$display("TB> getting L2 response");
		l2Cache.respDeq;
		l1CacheVec[procForReq].l2respl1(resp);
		state <= Ready;
	endrule
	
	/***********************************************
	Fill up interface for cpu and l1 communication
	************************************************/
	for (Integer i=0; i < valueOf(numCPU); i = i+1) begin
		cacheProcIF0[i] = interface L1Cache_Proc;
								method Action req(CPUToL1CacheReq r); 
									l1CacheVec[i].req(r);
								endmethod
								
								method ActionValue#(Data) resp;
									let cResp <- l1CacheVec[i].resp;
  									return cResp;                    
								endmethod
							endinterface;
	end
	interface cacheProcIF = cacheProcIF0;
	
	// get mem request from l2Cache
	method ActionValue#(MemReq) mReqDeq;
		let req <- l2Cache.mReqDeq;
		return req;
	endmethod
	
	// send mem response to l2Cache
	method Action memResp(MemResp r);
		l2Cache.memResp(r);
	endmethod
	
endmodule