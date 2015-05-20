import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import ProjectTypes::*;
import Fifo::*;

// Interface
interface L1Cache#(numeric type numCPU); 
	// assign ID
	method Action setID(Bit#(TLog#(numCPU)) id);
	method Bit#(TLog#(numCPU)) getID;
	
	//interface with CPU
	method Action req(CPUToL1CacheReq r); 
	method ActionValue#(Data) resp;

	//for printing the cache TODO:remove
	method BlockData getCellData(IndexL1 i, WayL1 j);
	method CacheCellType getCellState(IndexL1 i, WayL1 j);
	method TagL1 getCellTag(IndexL1 i, WayL1 j);

	//interface with L2
	method ActionValue#(L1ToL2CacheReq) l1Reql2; 
	method Action l2respl1(BlockData r); 
	method Bool ismReqQFull;
	method Bool ismModQFull;
	method Action l1ChangeInvGM(L2ReqToL1 r);
	method ActionValue#(BlockData) l1GetModified;
endinterface

// mkL1Cache module
module mkL1Cache(L1Cache#(numCPU));
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
	FIFOF#(L1ToL2CacheReq)  mReqQ <- mkFIFOF(); 
	FIFOF#(BlockData)       mRespQ <- mkFIFOF; 
	FIFOF#(L2ReqToL1)       l2ReqQ <- mkFIFOF;
	FIFOF#(BlockData)       l2RespQ <- mkFIFOF;
	
	Reg#(BlockLocationL1)  blockLocation <- mkRegU;
	Reg#(L1ForMiss)        miss <- mkRegU;
	Reg#(CacheStatusL1)    status <- mkReg(Ready);
	Reg#(Bit#(1)) 		   isInvGMReq <- mkReg(0);
	Reg#(Bit#(10))         missCnt <- mkReg(0);
	Reg#(Bit#(10))         hitCnt <- mkReg(0);
	Reg#(Bit#(TLog#(numCPU))) idReg <- mkRegU;
	 

	//rule//sendFillReq
	rule sendFillReq(status == SendFillReq); 
		let addr = miss.cReq.addr;
		let found = miss.found;
		WayL1 way = miss.way;
		
		let offset = blockLocation.offset;
		let idx = blockLocation.idx;
		let tag = blockLocation.tag;
		//check the condition
		if((miss.found == False) && (cntrSet[idx] >= fromInteger(valueof(WaysL1)))) //block is not in the $ and need to swap out a block
		begin
			$display("L1>In fill request L1 SO");
			Addr addrT = zeroExtend({tagArray[idx][way], idx});
			let dataT = dataArray[idx][way];
			mReqQ.enq(L1ToL2CacheReq{op: WB, addr: addrT, bData: dataT}); //no need to wait for a response
			miss <= L1ForMiss{cReq:miss.cReq, found:!found, way:way, data:miss.data}; 
		end
		else 
		begin
		
			$display("L1>In fill request L1 no SO");
			mReqQ.enq(miss.cReq);
			status <= WaitFillResp;
		end
	endrule
	
	//rule//waitFillResp
	rule waitFillResp(status == WaitFillResp); 
		let addr = miss.cReq.addr;
		let found = miss.found;
		WayL1 way = miss.way;
		
		let offset = blockLocation.offset;
		let idx = blockLocation.idx;
		let tag = blockLocation.tag;

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
		stateArray[idx][way] <= Modified;
		Vector#(Words, Bit#(DataSz)) words = unpack(dataArray[idx][way]); 
		words[offset] = miss.data; 
		dataArray[idx][way] <= pack(words);
		$display("L1> ID- %h, wrote to block",idReg);
		status <= Ready;
	endrule
	
	//rule//doInvGM - request from L2
	rule doInvGM(status == Ready && isInvGMReq == 1);
		L2ReqToL1 req = l2ReqQ.first;
		l2ReqQ.deq;
		$display("L1> ID %h, got invgm cmd %h",idReg,req.reqType);
		let offset =  blockLocation.offset;
		let idx =  blockLocation.idx;
		let tag =  blockLocation.tag;

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
	
	// print misses and hits for debug
	rule printMisses;
		$display("L1> ID- %h, State- %h Hits- %h, Misses - %h",idReg, status, hitCnt,missCnt);
		
	endrule
	
	//method//request from CPU
	method Action req(CPUToL1CacheReq r) if (status==Ready &&  isInvGMReq == 0);		
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
				status <= SendFillReq;
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
				$display("L1> ID- %h, wrote to block",idReg);
				
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
				status <= SendFillReq;
			end
		end
	endmethod
		
	//method//response to CPU
	method ActionValue#(Data) resp if (hitQ.notEmpty);
		hitQ.deq;
		return hitQ.first;
	endmethod
	
	//method//request to L2
	method ActionValue#(L1ToL2CacheReq) l1Reql2; 
		mReqQ.deq;
		return mReqQ.first;
	endmethod
	
	//method//response from L2
	method Action l2respl1(BlockData r); 
		mRespQ.enq(r);
	endmethod
	
	//method//check is there is a request to L2
	method Bool ismReqQFull;
		return mReqQ.notEmpty;
	endmethod
	
	//method//request from L2 for Inv/GM/InvGM
	method Action l1ChangeInvGM(L2ReqToL1 r) if (isInvGMReq == 0); 
		l2ReqQ.enq(r);
		isInvGMReq <= 1;
	endmethod
	
	// method// check if modified value is ready
	method Bool ismModQFull; 
		return l2RespQ.notEmpty;
	endmethod
		
	
	//method// response to L2 for GM/InvGM
	method ActionValue#(BlockData) l1GetModified if (l2RespQ.notEmpty); 
		l2RespQ.deq;
		return l2RespQ.first;
	endmethod
	
	//method//for printing the cache TODO:remove
	method BlockData getCellData(IndexL1 i, WayL1 j);
		return dataArray[i][j];		
	endmethod
	
	method CacheCellType getCellState(IndexL1 i, WayL1 j);
		return stateArray[i][j];		
	endmethod
	
	method TagL1 getCellTag(IndexL1 i, WayL1 j);
		return tagArray[i][j];		
	endmethod
	
	method Action setID(Bit#(TLog#(numCPU)) id);
		idReg <= id;
	endmethod
	
	method Bit#(TLog#(numCPU)) getID;
		return idReg;
	endmethod
	
endmodule

