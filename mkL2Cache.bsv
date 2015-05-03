import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import mkDirectory::*;
import ProjectTypes::*;



// interface
interface L2Cache#(numeric type numCPU);
	method ActionValue#(MemReq) mReqDeq;
	method Action memResp(MemResp r);
	method Action req(CacheReq#(numCPU) r);// if (status==Ready);
	method BlockData resp;// if (hitQ.notEmpty);
	method Action respDeq;
	method ActionValue#(L2ToNWCacheReq#(numCPU)) cacheInvDeq; // if (invQ.notEmpty);
	method Action cacheModifiedResp(BlockData data);// if (status == GetModified);
	//TODO: remove
	method Bit#(32) getMiss;
	method Bit#(32) getHit;
	method TypeDirStats#(numCPU) getDirStats(Addr addr);
endinterface

// mkL2Cache module
module mkL2Cache(L2Cache#(numCPU));
	// the cache data array
	Vector#(Rows,Vector#(Ways,Reg#(BlockData))) dataArray <- replicateM(replicateM(mkReg(0)));	
	// array to indicate if block is dirty (needs WB)
	Vector#(Rows, Vector#(Ways,Reg#(Bool)))    dirtyArray <- replicateM(replicateM(mkReg(False)));
	// cache blocks tags array
	Vector#(Rows, Vector#(Ways,Reg#(Tag)))  tagArray <- replicateM(replicateM(mkRegU));
	// counter for replacing policy for each index
	Vector#(Rows,Reg#(Way)) cntrArr <- replicateM(mkReg(0));
	// Bypass FIFOF for hit response
	FIFOF#(BlockLocation) hitQ <- mkBypassFIFOF();
	// Invalidate FIFOF
	FIFOF#(L2ToNWCacheReq#(numCPU)) invQ <- mkBypassFIFOF();
	// wb get modified value req FIFOF
	FIFOF#(BlockData) cacheModifiedQ <- mkBypassFIFOF(); //TODO: method to get modified val
	// write back block location
	
	Reg#(BlockLocation) blockLocation <- mkRegU;
	Reg#(CacheReq#(numCPU))     missReq <- mkRegU;
	Reg#(CacheStatus) status <- mkReg(Ready);
	FIFOF#(MemReq)   mReqQ <- mkFIFOF;
	//	FIFOF#(BlockData) mRespQ <- mkFIFOF;
	FIFOF#(MemResp) mRespQ <- mkFIFOF;
	Reg#(Bit#(numCPU)) modifier <- mkReg(0);
	Reg#(Bool) isHit <- mkReg(False);
	// directory
	Directory#(numCPU,Blocks) dir <- mkDirectory();
	//TODO: remove hit/miss counters
	Reg#(Bit#(32)) hitCntr <- mkReg(0);
	Reg#(Bit#(32)) missCntr <- mkReg(0);
	
	
	
	// function to calculate block number
	function BlockNum getBlockNum(Index idx,Way way);
			BlockNum res = zeroExtend(idx)*fromInteger(valueOf(Ways))+zeroExtend(way);
			return res;
	endfunction
	
	
	/* 
	TODO: remove:
	*/
	rule printL2CacheStatus;
		for (Integer i=0; i< valueOf(Rows); i = i+1) begin
			for (Integer j=0; j< valueOf(Ways); j = j+1) begin
				BlockNum bNum = getBlockNum(fromInteger(i),fromInteger(j));
				TypeDirStats#(numCPU) dStats = dir.getDirStats(bNum);
				$display("blocknum: %3d state: %1d present: %b Index: %4d Way: %2d",bNum,dStats.state,dStats.present,i,j);
				$display("data: %h",dataArray[i][j]);
			end
		end
	endrule
	
	
	// TODO: remove once debug is finished:
	rule printCacheState;
		String stateStr = "Ready";
		if (status == Ready) begin
			stateStr = "Ready";
		end
		else if (status == FillReq) begin
			stateStr = "FillReq";
		end
		else if (status == FillResp) begin
			stateStr = "FillResp";
		end
		else if (status == FillHit) begin
			stateStr = "FillHit";
		end
		else if (status == WrBack) begin
			stateStr = "WrBack";
		end
		else if (status == GetModified) begin
			stateStr = "GetModified";
		end
		else $display("Status could not be read");
		$display("Cache status is %s:",stateStr);
		$display("Misses: %d:",missCntr);
		$display("Hits: %d:",hitCntr);
	endrule
	
	// get modified value from modifier L1 cache
	rule doGetModified(status == GetModified);
		Index idx = blockLocation.idx;
		Way way = blockLocation.way;
		BlockData data = cacheModifiedQ.first;
		cacheModifiedQ.deq;
		dataArray[idx][way] <= data;
		if (isHit) begin
			status <= Ready;
			hitQ.enq(blockLocation);
		end
		else status <= WrBack;
	endrule

	// write back evacuated block to memory
	rule doWrBack(status == WrBack);
		Offset offset = truncate(missReq.addr);
		let idx = blockLocation.idx;
		let way = blockLocation.way;
		let addr = {pack(tagArray[idx][way]),pack(idx),pack(offset)};
		mReqQ.enq(MemReq{op:St,addr:addr,data:dataArray[idx][way],byteEn:?});
		status <= FillReq;
	endrule

	// request desired block from memory
	rule doFillReq (status==FillReq);
		mReqQ.enq(MemReq{op:Ld, addr:missReq.addr, data:?,byteEn:?});
		status <= FillResp;
	endrule

	// get response from memory, update data array
	rule doFillResp (status==FillResp);
		let data = mRespQ.first;  
		mRespQ.deq;
		Index idx = blockLocation.idx;
		Way way = blockLocation.way;
		Tag tag = truncateLSB(missReq.addr);
		tagArray[idx][way] <= tag;
		dataArray[idx][way] <= data;
		if (missReq.op == Rd) dirtyArray[idx][way] <= False;
		status <= FillHit;
		// move block state in directory to shared
		let dirRep <- dir.requestBlock(TypeDirReq{blockNum:getBlockNum(idx,way),op:missReq.op,proc:missReq.proc,dest:?});
	endrule
	
	// once memory returned value and updated in cache return value
	rule doFillHit (status==FillHit);
		hitQ.enq(blockLocation);
		status <= Ready;
	endrule

	
	method Action req(CacheReq#(numCPU) r) if (status==Ready);
		let offset = truncate(r.addr);
		// get index
		Index idx =	truncate(r.addr>>valueOf(OffsetSz));
		// get block tag
		Tag tag = truncateLSB(r.addr);
		// block way
		Way way = cntrArr[idx];
		// flag if tag found
		Bool found = False;
		// store the last request - used also if data is modified in one of child caches.
		missReq <= r;
		BlockLocation loc;
		loc.offset = offset;
		loc.idx = idx;
		// for tag match in cache index:
		for (Integer i=0; i<valueOf(Ways); i = i+1) begin
			if (tagArray[idx][i] == tag) begin
				way = fromInteger(i);
				found = True;
			end
		end		
		loc.way = way;
		blockLocation <= loc ;
		
		if (r.op != Rd) dirtyArray[idx][way] <= True;
		
		/**************************************************************************
		If block is not found - Need to replace existing block.
		1) Send directory request for WB from L2 to Mem.
		2) Send invalidate for all sharers OR get modified value.
		3) Go to WB state, and request new block from memory.
		****************************************************************************/
		if (!found) begin // miss - no tag match need to get from memory
			let dirRep <- dir.requestBlock(TypeDirReq{blockNum:getBlockNum(idx,way),op:WB,proc:r.proc,dest:DestMem});
			missCntr <= missCntr + 1;
			cntrArr[idx] <= cntrArr[idx]+1;
			if (dirRep.invVec != 0) begin
				invQ.enq(L2ToNWCacheReq{proc:dirRep.invVec,addr:r.addr,reqType:dirRep.reqType});
			end
			case (dirRep.pState) matches
				Shared:
					begin
						if (dirtyArray[idx][way]) begin
							status <= WrBack;
						end
						else status <= FillReq;
					end
				Modified:
					begin
						status <= GetModified;
					end
				Invalid: 
					begin
						status <= FillReq;
					end
			endcase
		end
		/***************************************************************************
		If block is found in state:
		Shared - return value.
		Modified - Inv or InvGM from modifier.
		Invalid - Not possible.
		****************************************************************************/
		else begin
			isHit <= True;
			let dirRep <- dir.requestBlock(TypeDirReq{blockNum:getBlockNum(idx,way),op:r.op,proc:r.proc,dest:DestL2});
			if (r.op != WB) hitCntr <= hitCntr + 1;
			if (dirRep.invVec != 0) begin
				invQ.enq(L2ToNWCacheReq{proc:dirRep.invVec,addr:r.addr,reqType:dirRep.reqType});
			end
			case (dirRep.pState) matches
				Shared:
					begin
						hitQ.enq(BlockLocation{idx:idx,way:way,offset:offset});
					end
				Modified:
					begin
						if (r.op == WB) begin 
							dataArray[idx][way] <= r.data;
						end
						else begin
							status <= GetModified;
						end
					end
			endcase
		end
	endmethod
	
	// get Invalidation L1 cache request.
	method ActionValue#(L2ToNWCacheReq#(numCPU)) cacheInvDeq if (invQ.notEmpty);
		invQ.deq;
		return invQ.first;
	endmethod
	
	// get modified block data
	method Action cacheModifiedResp(BlockData data) if (status == GetModified);
		cacheModifiedQ.enq(data);
	endmethod
	
	// return response to requesting cache
	method BlockData resp if (hitQ.notEmpty);// if (hitQ.notEmpty);
		let location = hitQ.first;
		let idx = location.idx;
		let way = location.way;
		return dataArray[idx][way];
	endmethod	
	
	// deq hit
	method Action respDeq; // if (hitQ.notEmpty);
		hitQ.deq;
	endmethod
	
	// memory gets request from L2
	method ActionValue#(MemReq) mReqDeq if (mReqQ.notEmpty);
		mReqQ.deq;
		return mReqQ.first;
	endmethod
	
	// memory returns data
	method Action memResp(MemResp r) if (mReqQ.notFull);
		mRespQ.enq(r);
	endmethod
	
	//TODO: remove
	/********************************************/
	method Bit#(32) getMiss;
		return missCntr;
	endmethod
	method Bit#(32) getHit;
		return hitCntr;
	endmethod
	method TypeDirStats#(numCPU) getDirStats(Addr addr);
		return dir.getDirStats(getBlockNum(blockLocation.idx,blockLocation.way));
	endmethod
	/********************************************/
endmodule

