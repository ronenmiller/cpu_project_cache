import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import ProjectTypes::*;

typedef struct{
    L1ToL2CacheReq cReq;
    Bool found;
	WayL1 way;
	Data data; //for write miss
} L1ForMiss deriving(Eq,Bits); 

// Interface
interface L1Cache; 
	//interface with CPU
	method Action req(CPUToL1CacheReq r); 
	method ActionValue#(Data) resp;
	
	//for printing the cache TODO:remove
	method ActionValue#(BlockData) getCellData(IndexL1 i, WayL1 j);
	method ActionValue#(CacheCellType) getCellState(IndexL1 i, WayL1 j);
	method ActionValue#(TagL1) getCellTag(IndexL1 i, WayL1 j);

	//interface with L2
	method ActionValue#(L1ToL2CacheReq) l1Req; 
	method Action l1Resp(BlockData r); 
	method ActionValue#(Bool) ismReqQFull;
	method Action l1ChangeInvGM(L2ReqToL1 r);
	method ActionValue#(BlockData) l1GetModified;
endinterface

// mkL1Cache module
module mkL1Cache(L1Cache);
	// the cache data array
	Vector#(RowsL1,Vector#(WaysL1,Reg#(BlockData)))  	 dataArray <- replicateM(replicateM(mkReg(0)));	
	// array to indicate if block is dirty (needs WB)
	Vector#(RowsL1, Vector#(WaysL1,Reg#(CacheCellType))) stateArray <- replicateM(replicateM(mkReg(Invalid)));
	// cache blocks tags array
	Vector#(RowsL1, Vector#(WaysL1,Reg#(TagL1)))          tagArray <- replicateM(replicateM(mkReg(0)));
	// counter for replacing policy for each index (the next place for a new block)    TODO: #
	Vector#(RowsL1,Reg#(WayL1))                           cntrArr <- replicateM(mkReg(0));
	// counter for number of entries to each set
	Vector#(RowsL1,Reg#(int))                             cntrSet <- replicateM(mkReg(0));
	
	// Bypass FIFOF 
	FIFOF#(Data)            hitQ <- mkBypassFIFOF(); //for hit response
	FIFOF#(L1ToL2CacheReq)  mReqQ <- mkFIFOF; //TODO: Fifo#(2, MemReq) memReqQ <- mkCFFifo;
	FIFOF#(BlockData)       mRespQ <- mkFIFOF; //TODO: Fifo#(2, Line) memRespQ <- mkCFFifo;
	FIFOF#(L2ReqToL1)       l2ReqQ <- mkFIFOF;
	FIFOF#(BlockData)       l2RespQ <- mkFIFOF;
	
	Reg#(BlockLocationL1)  blockLocation <- mkRegU;
	Reg#(L1ForMiss)        miss <- mkRegU;
	Reg#(CacheStatusL1)    status <- mkReg(Ready);
	Reg#(Bit#(1)) 		   isInvGMReq <- mkReg(0);
	Reg#(Bit#(10))         missCnt <- mkReg(0);
	Reg#(Bit#(10))         hitCnt <- mkReg(0);
	 
	//rule//startMiss
	rule startMiss(status == StartMiss); 
		let addr = miss.cReq.addr;
		let found = miss.found;
		WayL1 way = miss.way;
		
		let offset = blockLocation.offset;
		let idx = blockLocation.idx;
		let tag = blockLocation.tag;
		
		//Bit#(TLog#(Words)) offset = truncate(addr>>2);
		//IndexL1 idx = truncate(addr>>valueOf(OffsetSz));
		//TagL1 tag = truncateLSB(addr);
		
		//check the condition
		if((miss.found == False) && (cntrSet[idx] >= fromInteger(valueof(WaysL1)))) //block is not in the $ and need to swap out a block
		begin
			Addr addrT = zeroExtend({tagArray[idx][way], idx});
			let dataT = dataArray[idx][way];
			mReqQ.enq(L1ToL2CacheReq{op: WB, addr: addrT, bData: dataT}); //no need to wait for a response
		end
		status <= SendFillReq;
	endrule
	
	//rule//sendFillReq
	rule sendFillReq(status == SendFillReq); 
		mReqQ.enq(miss.cReq);
		status <= WaitFillResp;
	endrule
	
	//rule//waitFillResp
	rule waitFillResp(status == WaitFillResp); 
		let addr = miss.cReq.addr;
		let found = miss.found;
		WayL1 way = miss.way;
		
		let offset = blockLocation.offset;
		let idx = blockLocation.idx;
		let tag = blockLocation.tag;
		
		//Bit#(TLog#(Words)) offset = truncate(addr>>2);
		//IndexL1 idx = truncate(addr>>valueOf(OffsetSz));
		//TagL1 tag = truncateLSB(addr);

		let blockData = mRespQ.first;
		
		if(miss.found == False)
		begin
			cntrArr[idx] <= (way+1); //TODO: LRU
			tagArray[idx][way] <= tag;
		end
		
		dataArray[idx][way] <= blockData;
		
		case(miss.cReq.op) matches
			Rd:
			begin
				stateArray[idx][way] <= Shared;
				Vector#(Words, Bit#(DataSz)) words = unpack(blockData); 
				hitQ.enq(words[offset]);
				//print cache
				$display("PRINT3-start");
				for (Integer i=0 ; i<valueOf(RowsL1); i=i+1) begin
					for (Integer j=0 ; j<valueOf(WaysL1); j=j+1) begin			
						IndexL1 i1 = fromInteger(i);
						WayL1 j1 = fromInteger(j);
						$display("block in row %d way %d is :\n data - %h ;\n state - %b ;\n tag - %h",i1,j1,dataArray[i1][j1],stateArray[i1][j1],tagArray[i1][j1]);
					end
				end
				$display("PRINT3-end");
				status <= Ready;
			end
			Wr:
			begin
				status <= DoWrite;
			end
		endcase
		
		mRespQ.deq;
	endrule
	
	//rule//wrAfterResp
	rule wrAfterResp(status == DoWrite); 
		let addr = miss.cReq.addr;
		let found = miss.found;
		WayL1 way = miss.way;		
		
		let offset =  blockLocation.offset;
		let idx =  blockLocation.idx;
		
		//Bit#(TLog#(Words)) offset = truncate(addr>>2);
		//IndexL1 idx = truncate(addr>>valueOf(OffsetSz));

		stateArray[idx][way] <= Modified;
		Vector#(Words, Bit#(DataSz)) words = unpack(dataArray[idx][way]); 
		words[offset] = miss.data; 
		dataArray[idx][way] <= pack(words);
		
		//print cache
		$display("PRINT2-start");
		for (Integer i=0 ; i<valueOf(RowsL1); i=i+1) begin
			for (Integer j=0 ; j<valueOf(WaysL1); j=j+1) begin			
				IndexL1 i1 = fromInteger(i);
				WayL1 j1 = fromInteger(j);
				$display("block in row %d way %d is :\n data - %h ;\n state - %b ;\n tag - %h",i1,j1,dataArray[i1][j1],stateArray[i1][j1],tagArray[i1][j1]);
			end
		end
		$display("PRINT2-end");
		
		status <= Ready;
	endrule
	
	//rule//printStats 
	rule printStats(status==Ready);
		$display("L1 Cache %d requests: Hits: %d , Misses: %d",hitCnt+missCnt, hitCnt, missCnt);
	endrule
	
	//rule//doInvGM - request from L2
	rule doInvGM(status == Ready && isInvGMReq == 1);
		L2ReqToL1 req = l2ReqQ.first;
		l2ReqQ.deq;
		
		let offset =  blockLocation.offset;
		let idx =  blockLocation.idx;
		let tag =  blockLocation.tag;
		
		//Bit#(TLog#(Words)) offset = truncate(req.addr>>2);
		//IndexL1 idx = truncate(req.addr>>valueOf(OffsetSz)); //get index
		//TagL1 tag = truncateLSB(req.addr); //get block tag
		WayL1 way = 0;
		// find tag in set 
		for (Integer i=0; i<valueOf(WaysL1); i = i+1) begin
			if (tagArray[idx][i] == tag) begin
				way = fromInteger(i);
			end
		end
		
		case (req.reqType) matches
			Inv: //Invalidate
			begin
				l2RespQ.enq(0);
				stateArray[idx][way] <= Invalid;
			end
			GM: //Get Modified
			begin
				l2RespQ.enq(dataArray[idx][way]);
				stateArray[idx][way] <= Shared;
			end
			InvGM: //Invalidate+Get Modified
			begin
				l2RespQ.enq(dataArray[idx][way]);
				stateArray[idx][way] <= Invalid;
			end
		endcase
		isInvGMReq <= 0;
	endrule
	
	//method//request from CPU
	method Action req(CPUToL1CacheReq r) if (status==Ready &&  isInvGMReq == 0);
		$display("REQ"); //TODO
		//print cache
		$display("REQ-start");
		for (Integer i=0 ; i<valueOf(RowsL1); i=i+1) begin
			for (Integer j=0 ; j<valueOf(WaysL1); j=j+1) begin			
				IndexL1 i1 = fromInteger(i);
				WayL1 j1 = fromInteger(j);
				$display("block in row %d way %d is :\n data - %h ;\n state - %b ;\n tag - %h",i1,j1,dataArray[i1][j1],stateArray[i1][j1],tagArray[i1][j1]);
			end
		end
		$display("REQ-end");
		
		Bit#(TLog#(Words)) offset = truncate(r.addr>>2);
		$display("offset is %h", offset);//TODO
		IndexL1 idx = truncate(r.addr>>valueOf(OffsetSz)); //get index
		$display("idx is %h", idx);//TODO
		TagL1 tag = truncateLSB(r.addr); //get tag
		$display("tag is %h", tag);//TODO
		WayL1 way = cntrArr[idx]; //the next "available" way 
		
		Bool found = False; // flag if tag found
		
		//find tag in set 
		for (Integer i=0; i<valueOf(WaysL1); i = i+1) begin
			if (tagArray[idx][i] == tag) begin
				way = fromInteger(i);
				found = True;
			end
		end
		$display("way is %h", way);//TODO
		$display("block was %b", found);//TODO
		
		BlockLocationL1 loc;
		loc.offset = offset;
		loc.idx = idx;
		loc.tag = tag;
		
		blockLocation <= loc ;
		
		let data = dataArray[idx][way];
		let state = stateArray[idx][way];
		
		if(r.op == Rd) //read
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
				L1ToL2CacheReq rqR;
				rqR.op = r.op;
				rqR.addr = r.addr; 
				rqR.bData = ?; //no need for bData	
				
				miss <= L1ForMiss{cReq:rqR, found:found, way:way, data:?}; //data for write only
				status <= StartMiss;
			end
		end
    
		else if (r.op == Wr) //write
		begin
			if(found && (state == Modified)) //block is in the $ and is in M
			begin //do write
				hitCnt <= hitCnt+1; 
				Vector#(Words, Bit#(DataSz)) words = unpack(dataArray[idx][way]); 
				words[offset] = r.data; 
				dataArray[idx][way] <= pack(words);
				
				//print cache
				$display("PRINT1-start");
				for (Integer i=0 ; i<valueOf(RowsL1); i=i+1) begin
					for (Integer j=0 ; j<valueOf(WaysL1); j=j+1) begin			
						IndexL1 i1 = fromInteger(i);
						WayL1 j1 = fromInteger(j);
						$display("block in row %d way %d is :\n data - %h ;\n state - %b ;\n tag - %h",i1,j1,dataArray[i1][j1],stateArray[i1][j1],tagArray[i1][j1]);
					end
				end
				$display("PRINT1-end");
			end
			else //block is not in the $ or is I/S
			begin 
				//go to L2 (change state to modified)
				missCnt <= missCnt+1; 
				L1ToL2CacheReq rqW;
				rqW.op = r.op;
				rqW.addr = r.addr;
				rqW.bData = ?; //no need for bData	
				
				miss <= L1ForMiss{cReq:rqW, found:found, way:way, data:r.data};  
				status <= StartMiss;
			end
		end
	endmethod
		
	//method//response to CPU
	method ActionValue#(Data) resp;
		hitQ.deq;
		return hitQ.first;
	endmethod
	
	//method//request to L2
	method ActionValue#(L1ToL2CacheReq) l1Req; 
		//return mReqQ.deq;
		mReqQ.deq;
		return mReqQ.first;
	endmethod
	
	//method//response from L2
	method Action l1Resp(BlockData r); 
		mRespQ.enq(r);
	endmethod
	
	//method//check is there is a request to L2
	method ActionValue#(Bool) ismReqQFull;
		return mReqQ.notEmpty;
	endmethod
	
	//method//request from L2 for Inv/GM/InvGM
	method Action l1ChangeInvGM(L2ReqToL1 r) if (isInvGMReq == 0); 
		l2ReqQ.enq(r);
		isInvGMReq <= 1;
	endmethod
	
	//method// response to L2 for GM/InvGM
	method ActionValue#(BlockData) l1GetModified; 
		//return l2RespQ.deq;
		l2RespQ.deq;
		return l2RespQ.first;
	endmethod
	
	//method//for printing the cache TODO:remove
	method ActionValue#(BlockData) getCellData(IndexL1 i, WayL1 j);
		return dataArray[i][j];		
	endmethod
	
	method ActionValue#(CacheCellType) getCellState(IndexL1 i, WayL1 j);
		return stateArray[i][j];		
	endmethod
	
	method ActionValue#(TagL1) getCellTag(IndexL1 i, WayL1 j);
		return tagArray[i][j];		
	endmethod
	
endmodule
