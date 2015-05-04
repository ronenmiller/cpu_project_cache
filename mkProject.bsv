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
	Reg#(Bit#(2)) stepL1Req 	         <- mkReg(0);
	Reg#(Bit#(1)) isL2Req                <- mkReg(0);
	Reg#(Bit#(numCPU)) invGMProc         <- mkReg(0);
	Reg#(Bit#(TLog#(numCPU))) cntReq     <- mkReg(0);
	Reg#(Bit#(TLog#(numCPU))) procForReq <- mkReg(0);
	
	Reg#(Bool) start <- mkReg(False);
	
	
	// find which L1 will send request to L2
	rule checkL1Req(stepL1Req == 0);
		//Bit#(TLog#(numCPU)) cnt = cntReq;
		Bit#(TLog#(numCPU)) cnt = 1;
		
		Bool flag = False;
		//for(Integer i=unpack(cntReq) ; (i<valueof(numCPU) && flag == False) ; i=i+1)
		/*while (cnt < fromInteger(valueOf(numCPU)) && flag == False)
		begin
			let tmp <- l1CacheVec[cnt].ismReqQFull;
			if(tmp == True) begin //if there is a request from the next L1 cache
				stepL1Req <= 1;
				procForReq <= cnt;
				$display("TB> L1 number %d will send to L2 a request",procForReq);
				if (cnt == (fromInteger(valueOf(numCPU))-1)) begin 
					cntReq <= 0;
				end
				else begin
					cntReq <= cnt+1;
				end
				flag = True; //break the for loop
				stepL1Req <= 1;
			end
			
			/*else if (tmp == False && cnt == (fromInteger(valueOf(numCPU))-1)) begin //else check the next L1 cache
				cnt = 0;
			end
			else begin
				cnt = cnt+1;
			end
		end*/
		procForReq <= 0; //
		stepL1Req <= 1;//
	endrule
	
	// L1 sends request to L2, L2 receives request from L1
	rule l1SendL2Req(stepL1Req == 1);
		Bit#(TLog#(numCPU)) proc = procForReq;
		L1ToL2CacheReq l1ToL2Req <- l1CacheVec[proc].l1Req;
		$display("TB> L1 number %d sends L2 request for address 0x%h",proc, l1ToL2Req.addr);
		
		CacheReq#(numCPU) l1ToL2REQ;
		l1ToL2REQ.op = l1ToL2Req.op;
		l1ToL2REQ.addr = l1ToL2Req.addr;
		l1ToL2REQ.data = l1ToL2Req.bData;
		l1ToL2REQ.proc = (1<<proc);
		l2Cache.req(l1ToL2REQ);
		stepL1Req <= 2;
	endrule
	
	// L2 sends response to L1, L1 receives response from L2 
	rule l2SendRespL1(stepL1Req == 2);
		let resp = l2Cache.resp;
		$display("TB> sending L2 response with data 0x%h",resp);
		//l2Cache.respDeq;	
		
		l1CacheVec[procForReq].l1Resp(resp);
		stepL1Req <= 0;
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
		BlockData resp = 0;
		for (Integer i=0 ; i < valueof(numCPU) ; i = i+1)
		begin
			if (invGMProc[i] == 1) begin
				resp <- l1CacheVec[i].l1GetModified;
				//l2Cache.cacheModifiedResp(resp);
				$display("TB> sending L1 response to L2 with data 0x%h",resp);
			end
		end
	
		stepL1Req <= 0;
	endrule
	
	// get mem request from l2Cache
	method ActionValue#(MemReq) mReqDeq;
		let req <- l2Cache.mReqDeq;
		return req;
	endmethod
	
	// send mem response to l2Cache
	method Action memResp(MemResp r);
		l2Cache.memResp(r);
	endmethod
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
	
endmodule





