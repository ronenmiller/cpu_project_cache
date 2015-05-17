import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import ProjectTypes::*;
import Fifo::*;

// Interface
interface L1Cache; 
	//interface with CPU
	method Action req(CPUToL1CacheReq r); 
	method ActionValue#(Data) resp;
	method Action l1Reql2Deq;
	
	//interface with L2
	method ActionValue#(L1ToL2CacheReq) l1Reql2; 
	method Action l2respl1(BlockData r);
	method Bool ismReqQFull;
	method Action invGMCommand(L2ReqToL1 r);
	method ActionValue#(BlockData) sendModified;
	method ActionValue#(BlockData) modifiedDeq;
endinterface


module mkL1Cache(L1Cache);
	// the cache data array
	Vector#(RowsL1,Vector#(WaysL1,Reg#(BlockData)))  	 dataArray 	<- replicateM(replicateM(mkReg(0)));	
	// array to indicate if block is dirty (needs WB)
	Vector#(RowsL1, Vector#(WaysL1,Reg#(CacheCellType))) stateArray <- replicateM(replicateM(mkReg(Invalid)));
	// cache blocks tags array
	Vector#(RowsL1, Vector#(WaysL1,Reg#(TagL1)))          tagArray 	<- replicateM(replicateM(mkReg(0)));
	// counter for replacing policy for each index (the next place for a new block)    TODO: #
	Vector#(RowsL1,Reg#(WayL1))                           cntrArr 	<- replicateM(mkReg(0));
	// counter for number of entries to each set
	Vector#(RowsL1,Reg#(int))                             cntrSet 	<- replicateM(mkReg(0));
	
	// Bypass FIFOF 
	FIFOF#(Data)            hitQ <- mkBypassFIFOF(); //for hit response
	FIFOF#(L1ToL2CacheReq)  mReqQ <- mkFIFOF(); //TODO: Fifo#(2, MemReq) memReqQ <- mkCFFifo;
	//Fifo#(2, L1ToL2CacheReq) mReqQ <- mkCFFifo;
	FIFOF#(BlockData)       mRespQ <- mkFIFOF; //TODO: Fifo#(2, Line) memRespQ <- mkCFFifo;
	FIFOF#(L2ReqToL1)       l2ReqQ <- mkFIFOF;
	FIFOF#(BlockData)       l2RespQ <- mkFIFOF;
	
	Reg#(BlockLocationL1)  blockLocation <- mkRegU;
	Reg#(L1ForMiss)        miss <- mkRegU;
	Reg#(CacheStatusL1)    status <- mkReg(Ready);
	Reg#(Bool) 		   isInvGMReq <- mkReg(0);
	Reg#(Bit#(10))         missCnt <- mkReg(0);
	Reg#(Bit#(10))         hitCnt <- mkReg(0);


	method req(CPUToL1CacheReq r) if (status == ready && isInvGMReq == False);
		Bit#(TLog#(Words)) offset = truncate(r.addr>>2);
		IndexL1 idx = truncate(r.addr>>valueOf(OffsetSz)); //get index
		TagL1 tag = truncateLSB(r.addr); //get tag
		WayL1 way = cntrArr[idx]; //the next "available" way 
		Bool found = False; // flag if tag found
		
		//find tag in set 
		for (Integer i=0; i<valueOf(WaysL1); i = i+1) begin
			if (tagArray[idx][i] == tag) begin
				way = fromInteger(i);
				found = True;
			end
		end
		
		BlockLocationL1 loc;
		loc.offset = offset;
		loc.idx = idx;
		loc.tag = tag;
		
		blockLocation <= loc ;
		
		let data = dataArray[idx][way];
		let bState = stateArray[idx][way];

		L1ToL2CacheReq rq;
		rq.op = r.op;
		rq.addr = r.addr; 
		rq.bData = ?; //no need for bData
		
		case (r.op) matches
		Rd: //read
		begin
			if(found && (state != Invalid)) //block is in the $ and is S/M
			begin
				hitCnt <= hitCnt+1; 
				Vector#(Words, Bit#(DataSz)) words = unpack(data); 
				hitQ.enq(words[offset]); //state doesnt change
			end
			else //block is not in the $ or block is I
			begin
				//go to L2 (change state to shared) 
				missCnt <= missCnt+1; 
				miss <= L1ForMiss{cReq:rq, found:found, way:way, data:?}; //data for write only
				status <= SendFillReq;
			end
		end
		Wr: //write
		begin
			if(found && (state == Modified)) //block is in the $ and is in M
			begin //do write
				hitCnt <= hitCnt+1; 
				Vector#(Words, Bit#(DataSz)) words = unpack(dataArray[idx][way]); 
				words[offset] = r.data; 
				dataArray[idx][way] <= pack(words);
			end
			else //block is not in the $ or is I/S
			begin 
				//go to L2 (change state to modified)
				missCnt <= missCnt+1; 				
				miss <= L1ForMiss{cReq:rq, found:found, way:way, data:r.data};  
				status <= SendFillReq;
			end
		end
	endmethod




