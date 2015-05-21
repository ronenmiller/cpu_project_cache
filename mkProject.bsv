import FIFOF::*;
import Vector::*;
import mkL1Cache::*;
import mkL2Cache::*;
import ProjectTypes::*;
import Arbiter::*;
import Connectable::*;


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
	
	// cpu to l1 interface vector - see fill later on
	Vector#(numCPU, L1Cache_Proc) cacheProcIF0;
	
	// create L1 cache
	Vector#(numCPU,L1Cache#(numCPU)) l1CacheVec <- replicateM(mkL1Cache);
	
	// create L2 cache
	L2Cache#(numCPU) l2Cache <- mkL2Cache();
	
	// Regs & FIFOS
	Reg#(Bit#(numCPU)) 			invGMProc   <- mkReg(0);
	Reg#(L2ReqL1) 				invType   	<- mkReg(None);
	Reg#(Bit#(TLog#(numCPU))) 	cntReq     	<- mkReg(0);
	Reg#(Bit#(TLog#(numCPU))) 	procForReq 	<- mkReg(0);
	Reg#(ProjState) 			state		<- mkReg(Ready);
	Reg#(Bool)					inited		<- mkReg(False);
	
	function Action doSend(L1Cache#(numCPU) c); 
   		action 
      		let req <- c.l1Reql2; 
      		let proc = c.getID;
      		procForReq <= proc;
		    // do something with the value 
		    CacheReq#(numCPU) reqToL2;
			reqToL2.op = req.op;
			reqToL2.addr = req.addr;
			reqToL2.data = req.bData;
			reqToL2.proc = (1<<proc);
			l2Cache.req(reqToL2);
			state <= WaitL2Resp;
   		endaction 
   	endfunction
	
	// function to create an ArbiterRequest_IFC 
	function ArbiterRequest_IFC mkArbReq(L1Cache#(numCPU) c); 
		return 
			(interface ArbiterRequest_IFC; 
				method request() = (c.ismReqQFull && state == Ready); 
     			// no lock required 
     			method lock() = False;
     			// when granted, perform the action 
     			method grant() = doSend(c); 
       		 endinterface);  
   endfunction 
   
   
   /********************************************
   	Connecting Arbiter for L1 to L2 requests
   	*******************************************/
   	
   	// the request ifcs 
   	Vector#(numCPU, ArbiterRequest_IFC) rqs = map(mkArbReq, l1CacheVec); 
   	// the arbiter 
   	Arbiter_IFC#(numCPU) arb <- mkArbiter(False); 
   	// connect the reqs to the clients 
   	mkConnection(arb.clients, rqs); 
   
    /********************************************
   	Connecting Arbiter for L1 to L2 requests
   	*******************************************/
   
   	// inited after first cycle
   	rule init;
   		inited <= True;
   	endrule
   	
   	// L2 sends response to L1, L1 receives response from L2 
	rule l2SendRespL1(state == WaitL2Resp);
		let proc = procForReq;
		let resp <- l2Cache.resp;
		$display("TB> getting L2 response");
		l2Cache.respDeq;
		l1CacheVec[proc].l2respl1(resp);
		state <= Ready;
	endrule

	// L2 sends request to L1 for Inv/GM/InvGM
	rule l2SendL1InvGM;
		L2ToNWCacheReq#(numCPU) l2ToL1Req <- l2Cache.cacheInvDeq; // l2 sends request 
		
		//$display("TB> L2 sends L1 request %d for address 0x%h proc %b" ,l2ToL1Req.reqType, l2ToL1Req.addr, l2ToL1Req.proc);
		//change type L2ToNWCacheReq to L2ReqToL1 in order to transfer the request to l1 
		L2ReqToL1 l2ToL1REQ;
		l2ToL1REQ.addr = l2ToL1Req.addr;
		l2ToL1REQ.reqType = l2ToL1Req.reqType;
		Bit#(numCPU) proc = l2ToL1Req.proc;
		
		//save the proc and the request type
		invGMProc <= l2ToL1Req.proc;
		invType <= l2ToL1Req.reqType;
		
		//according to the proc_vec send to the l1's the request
		for (Integer i=0 ; i < valueof(numCPU) ; i = i+1)
		begin
			if (proc[i] == 1) begin
				l1CacheVec[i].l1ChangeInvGM(l2ToL1REQ);
			end
		end
	endrule
	
   	
	for (Integer i=0; i < valueOf(numCPU); i = i+1) begin
		/***********************************************
		Fill up interface for cpu and l1 communication
		************************************************/
		cacheProcIF0[i] = 
			interface L1Cache_Proc;
				method Action req(CPUToL1CacheReq r); 
					l1CacheVec[i].req(r);
				endmethod
				
				method ActionValue#(Data) resp;
					let cResp <- l1CacheVec[i].resp;
					return cResp;                    
				endmethod
			endinterface;
		
		// initialize logical id for each cache
		rule initID(inited == False);
			l1CacheVec[i].setID(fromInteger(i));
		endrule
		
		// get modified value from l1 to l2
		rule fillModVal(state != Ready);
			let val <- l1CacheVec[i].l1GetModified; 
		    l2Cache.cacheModifiedResp(val);
		    $display("mkProj> returned modified value from l1 to l2 %h",val);
		endrule
	end
	
	
	// connect interface
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
