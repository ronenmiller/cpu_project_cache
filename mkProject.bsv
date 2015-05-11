import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import mkL1Cache::*;
import mkL2Cache::*;
import ProjectTypes::*;
import ConfigReg :: * ;


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
	Reg#(Bit#(1)) isL2Req                	<- mkReg(0);
	Reg#(Bit#(numCPU)) invGMProc         	<- mkReg(0);
	Reg#(UInt#(TLog#(numCPU))) cntReq     	<- mkReg(0);
	Reg#(UInt#(TLog#(numCPU))) procForReq 	<- mkConfigReg(0);
	Reg#(ProjState) state					<- mkReg(Ready);
	Reg#(CacheReq#(numCPU)) l1ToL2Req		<- mkRegU;

	
	// find out which L1 will send request to L2
	rule checkL1Req(state == Ready);
		UInt#(TLog#(numCPU)) cnt = cntReq;
		$display("TB> Checking for L1 to L2 request...");
		Bool flag = False;
		for(Integer i = 0 ; (i<valueof(numCPU) && flag == False) ; i=i+1)
		begin
			let isFull = l1CacheVec[cnt].ismReqQFull;
			$display("TB> Checking for L1[%h] isFull: %b",cnt,isFull);
			if(isFull == True) begin //if there is a request from the next L1 cache
				let reqFromL1 <- l1CacheVec[i].l1Reql2;
				CacheReq#(numCPU) reqToL2;
				reqToL2.op = reqFromL1.op;
				reqToL2.addr = reqFromL1.addr;
				reqToL2.data = reqFromL1.bData;
				reqToL2.proc = (1<<cnt);
				l1ToL2Req <= reqToL2;
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

	// send request from L1 to L2
	rule sendReqToL2(state == SendL2Req);
		l2Cache.req(l1ToL2Req); 
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
	
	// L2 sends request to L1 for Inv/GM/InvGM
	rule l2SendL1InvGM(isL2Req == 0);
		L2ToNWCacheReq#(numCPU) l2ToL1Req <- l2Cache.cacheInvDeq; // l2 sends request 
		$display("TB> L2 sends L1 request %d for address 0x%h" ,l2ToL1Req.reqType, l2ToL1Req.addr);
		
		//change type L2ToNWCacheReq to L2ReqToL1 in order to transfer the request to l1 
		L2ReqToL1 l2ToL1REQ;
		l2ToL1REQ.addr = l2ToL1Req.addr;
		l2ToL1REQ.reqType = l2ToL1Req.reqType;
		Bit#(numCPU) proc = l2ToL1Req.proc;
		
		//save the proc_vec given by l2 (indicates which processes need to do the requst)
		// for use of rule l1SendRespL2
		invGMProc <= l2ToL1Req.proc;
		
		//according to the proc_vec send to the l1's the request
		for (Integer i=0 ; i < valueof(numCPU) ; i = i+1)
		begin
			if (proc[i] == 1) begin
				l1CacheVec[i].l1ChangeInvGM(l2ToL1REQ);
			end
		end
		
		//flag the rule l1SendRespL2 to start
		isL2Req <= 1;
	endrule
	
	// L1 sends response to L2
	rule l1SendRespL2(isL2Req == 1);
		Vector#(numCPU,BlockData) respVec = replicate(0);
		Bit#(TLog#(numCPU)) modProc = 0;
		//according to the proc_vec get the l1's response and send it to l2
		for (Integer i=0 ; i < valueof(numCPU) ; i = i+1)
		begin
			if (invGMProc[i] == 1) begin
				respVec[i] <- l1CacheVec[i].l1GetModified;
				$display("TB> sending L1 response to L2 with data 0x%h",respVec[i]);
				modProc = fromInteger(i);
			end
		end
		l2Cache.cacheModifiedResp(respVec[modProc]);
		isL2Req <= 0;
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
