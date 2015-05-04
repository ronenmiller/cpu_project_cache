import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import mkL1cache::*;
import mkL2cache::*;
import ProjectTypes::*;



// interface
interface Project#(numeric type numCPU);
	interface Vector#(numCPU, L1Cache) cacheProc;

endinterface

// mkProject module
module mkProject(L2Cache#(numCPU));
	Vector#(numCPU, L1Cache) cacheProc0;

	for (Integer i=0; i < valueOf(numCPU); i = i+1) 
	begin
		cacheProc0[i] = interface L1Cache;
							method Action req(CPUToL1CacheReq r); 
								L1Cache.req(r);//?
							endmethod
							
							method ActionValue#(Data) resp;
                                L1Cache.resp;    //?                          
							endmethod

							method ActionValue#(L1ToL2CacheReq) l1Req; 
								L1Cache.l1Req;//?
							endmethod

							method Action l1Resp(BlockData r); 
								L1Cache.l1Resp(r);//?
							endmethod

							method Action l1ChangeInvGM(L2ReqToL1 r);
								L1Cache.l1ChangeInvGM(r);//?
							endmethod

							method ActionValue#(BlockData) l1GetModified;
								L1Cache.l1GetModified;
							endmethod
						endinterface;
	end

	interface cacheProc = cacheProc0;
	
	// create L1 cache
	Vector#(numCPU,L1Cache) l1CacheVec <- replicateM(mkL1Cache);
	
	// create L2 cache
	L2Cache#(numCPU) l2 <- mkL2Cache();
	
	// Reg
	Reg#(Bit#(2)) isL1Req 	 <- mkReg(0);
	Reg#(Bit#(1)) isL2Req    <- mkReg(0);
	Reg#(Bit#(10)) invGMProc <- mkReg(0);
	Reg#(Bit#(10)) cntReq    <- mkReg(0);
	
	// L1 sends request to L2, L2 receives request from L1
	rule l1SendL2Req(isL1Req == 0);
		L1ToL2CacheReq l1ToL2Req <- l1.l1Req;
		$display("TB> L1 sends L2 request for address 0x%h",l1ToL2Req.addr);
		
		CacheReq#(numCPU) l1ToL2REQ;
		l1ToL2REQ.op = l1ToL2Req.op;
		l1ToL2REQ.addr = l1ToL2Req.addr;
		l1ToL2REQ.data = l1ToL2Req.bData;
		l1ToL2REQ.proc = //TODO:how to get proc????
		l2.req(l1ToL2REQ);
		isL1Req <= 1;
	endrule
	
	// L2 sends response to L1
	rule l2SendRespL1(isL1Req == 1);
		BlockData resp <- l2.resp;
		$display("TB> sending L2 response with data 0x%h",resp);
		
		l1.l1Resp(resp);
		isL1Req <= 2;
	endrule

	// L1 receives response from L2 
	rule l2SendRespL1(isL1Req == 2);
		l2.respDeq;		
		l1.l1Resp(resp);
		isL1Req <= 0;
	endrule	
	
	// L2 sends request to L1 for Inv/GM/InvGM
	rule l2SendL1InvGM(isL2Req == 0);
		L2ToNWCacheReq#(numCPU) l2ToL1Req <- l2.cacheInvDeq; 
		$display("TB> L2 sends L1 request %d for address 0x%h" ,l2ToL1Req.reqType, l2ToL1Req.addr);
		
		L2ReqToL1 l2ToL1REQ;
		l2ToL1REQ.addr = l2ToL1Req.addr;
		l2ToL1REQ.reqType = l2ToL1Req.reqType;
		Bit#(numCPU) proc = l2ToL1Req.proc;
		
		invGMProc <= l2ToL1Req.proc; // for use of rule l1SendRespL2
		
		for (Integer i=0 ; i < numCPU ; i = i+1)
		begin
			if (proc[i] == 1) begin
				l1CacheVec[i].l1ChangeInvGM(l2ToL1REQ);
			end
		end
	
		isL2Req <= 1;
	endrule
	
	// L1 sends response to L2
	rule l1SendRespL2(isL2Req == 1);
		BlockData resp;
		for (Integer i=0 ; i < numCPU ; i = i+1)
		begin
			if (invGMProc[i] == 1) begin
				resp <- l1CacheVec[i].l1GetModified;
				l2.cacheModifiedResp(resp);
				$display("TB> sending L1 response to L2 with data 0x%h",resp);
			end
		end
	
		isL1Req <= 0;
	endrule
	
/*	
	typedef struct{
	Bit#(numCPU) proc;
	Addr		 addr;
	L2ReqL1		 reqType;
} L2ToNWCacheReq#(numeric type numCPU) deriving(Eq,Bits);
	
	/*
	typedef struct{
    CacheOp op;
    Addr  addr;
	BlockData bData;
} L1ToL2CacheReq deriving(Eq,Bits); 

typedef struct{
    Addr addr;
    L2ReqL1 reqType;
} L2ReqToL1 deriving(Eq,Bits); 

	typedef struct{
    CacheOp op;
    Addr  addr;
    BlockData  data;
    Bit#(numCPU) proc; // the requesting processor
} CacheReq#(numeric type numCPU) deriving(Eq,Bits); */
	/*l1
	
	method Action req(CPUToL1CacheReq r); 
	method ActionValue#(Data) resp;
	
	method ActionValue#(L1ToL2CacheReq) l1Req; 
	method Action l1Resp(BlockData r); 
	method Action l1ChangeInvGM(L2ReqToL1 r);
	method ActionValue#(BlockData) l1GetModified;
	*/
	/*l2
	method ActionValue#(MemReq) mReqDeq;
	method Action memResp(MemResp r);
	method Action req(CacheReq#(numCPU) r);// if (status==Ready);
	method BlockData resp;// if (hitQ.notEmpty);
	method Action respDeq;
	method ActionValue#(L2ToNWCacheReq#(numCPU)) cacheInvDeq; // if (invQ.notEmpty);
	method Action cacheModifiedResp(BlockData data);// if (status == GetModified);
	*/
	
	
	
endmodule





