/***************************
	Imports:
****************************/
import Vector::*;
import ProjectTypes::*;

/***************************
	defines and structs:
****************************/
/* destination of writeback*/
typedef enum{DestMem,DestL2} WBDest deriving (Bits, Eq);
/* struct to hold request from L2 $ to directory. */
typedef struct {
	BlockNumL2 blockNum;
	CacheOp op; // chache request opcode: 0 - read, 1 - write, 2 - write_back
	Bit#(numCPU) proc; // processor number
	WBDest dest;
} TypeDirReq#(numeric type numCPU,numeric type blocks) deriving (Bits, Eq);

/* struct to hold request to specific line. */
typedef struct {
	CacheOp op; // chache request opcode: 0 - read, 1 - write, 2 - write_back
	Bit#(numCPU) proc; // processor number
	WBDest dest;
} TypeDirLineReq#(numeric type numCPU) deriving (Bits, Eq);

/* struct to hold reply from directory to $. */
typedef struct {
	Bit#(numCPU) invVec; // invalidate or get modified block in chaches
	StateType pState;
	StateType nState;
	L2ReqL1	  reqType;
} TypeDirRep#(numeric type numCPU) deriving (Bits, Eq);

/****************************************************
	Module to define a single line in the directory
*****************************************************/

/* Interface: DirLine */
interface DirLine#(numeric type numCPU);
	method ActionValue#(TypeDirRep#(numCPU)) request(TypeDirLineReq#(numCPU) req);
	method TypeDirStats#(numCPU) getDirStats;
endinterface

/* Module: mkDirLine */
module mkDirLine (DirLine#(numCPU));
	Reg#(Bit#(numCPU)) present <- mkReg(0); // Indicates if block is cached for each processor.
	Reg#(StateType) state <- mkReg(Invalid); // directory fsm state of block: 0 - Shared, 1 - Modified, 2 - Invalid.
	//Reg#(Bit#(numCPU)) modifier <- mkReg(0); // if block is modified - who is the modifier.

	/**********************************************************************
		ActionValue method  : request
		receives			: numCPU - type to define number of cpu's.
				  			  TypeDirLineReq req - holds block request details.
		returns				: TypeDirRep rep - struct that holds reply from line 
				  			  to dir.
	**********************************************************************/

	method ActionValue#(TypeDirRep#(numCPU)) request(TypeDirLineReq#(numCPU) req);
		TypeDirRep#(numCPU) rep;
		rep.invVec = 0;
		rep.pState = Invalid;
		rep.nState = Invalid;
		rep.reqType = None;
		if (req.op == Rd) begin //read
			case (state) matches
				Shared: 
					begin
						present <= present | req.proc;
						state <= Shared;
						rep.nState = Shared;
					end
				Modified:
					begin
						present <= present | req.proc;
						state <= Shared;
						rep.nState = Shared;
						rep.invVec = present;
						rep.reqType = GM;
					end
				Invalid:
					begin
						present <= req.proc;
						state <= Shared;
						rep.nState = Shared;
					end
			endcase
		end
		else if (req.op == Wr) begin //write
			case (state) matches
				Shared: 
					begin
						present <= req.proc;
						rep.invVec = present;// & (~req.proc);
						state <= Modified;
						rep.nState = Modified;
						rep.reqType = Inv;
					end
				Modified:
					begin
						rep.invVec = present;
						rep.reqType = InvGM;
						present <= req.proc;
						rep.nState = Modified;
					end
				Invalid:
					begin	
						present <= req.proc;
						state <= Modified;
						rep.nState = Modified;
					end	
			endcase
		end
		/*********************************************
		 1) WB request from L1 - swap out from l1 cache.
			In this case does not need to do anything, 
			just change state to shared. (originally modified)
		 2) 
		 **********************************************/
		else if (req.op == WB) begin 
			case (state) matches
				Shared:
					begin
						rep.invVec = present;
						present <= 0;
						state <= Invalid;
						rep.nState = Invalid;
						rep.reqType = Inv;
					end
				Modified:
					begin
						if(req.dest == DestMem) begin // write back request by L2
							rep.invVec = present;						
							present <= 0;
							state <= Invalid;
							rep.nState = Invalid;
							rep.reqType = Inv;
						end
						else begin // write back request from L1 dest == DestL2
							rep.invVec = 0;						
							present <= 0;
							state <= Shared;
							rep.nState = Shared;
						end
					end
			endcase
		end
		rep.pState = state;
		return rep;		
	endmethod
	/****************************
	TODO: remove
	****************************/
	method TypeDirStats#(numCPU) getDirStats;
		return TypeDirStats{present:present,state:state};
	endmethod
endmodule

/****************************************************
	Module to define a the directory to keep blocks
	coherence between multiple clients.
*****************************************************/

/* Interface: Directory */
interface Directory#(numeric type numCPU,numeric type blocks);
	method ActionValue#(TypeDirRep#(numCPU)) requestBlock(TypeDirReq#(numCPU,blocks) req);
	method TypeDirStats#(numCPU) getDirStats(BlockNumL2 blockNum);
endinterface

/*********************************************************
   Module: mkDirectory
   receives: numCPU - type to define number of cpu's.
   			 blocks - Number of blocks in cache
**********************************************************/
   
module mkDirectory(Directory#(numCPU,blocks));
	Vector#(blocks,DirLine#(numCPU)) dir <- replicateM(mkDirLine());
	/*
	//TODO:remove
	rule printBlockState;
		for (Integer i=0 ; i<valueOf(Blocks); i=i+1) begin
			let stats = dir[i].getDirStats;
			$display("block %d state is : %b present is %b",i,stats.state,stats.present);
		end
	endrule
	*/
	/**********************************************************************
		ActionValue method  : request
		receives			: numCPU - type to define number of cpu's.
				  			  TypeDirLineReq req - holds block request details.
		returns				: TypeDirRep rep - struct that holds reply from 
							  directory to $.
	**********************************************************************/
	method ActionValue#(TypeDirRep#(numCPU)) requestBlock(TypeDirReq#(numCPU,blocks) req);
		TypeDirRep#(numCPU) rep <- dir[req.blockNum].request(TypeDirLineReq{op:req.op, proc:req.proc,dest:req.dest});
		return rep;
	endmethod

	
	/****************************
	TODO: remove
	****************************/
	method TypeDirStats#(numCPU) getDirStats(BlockNumL2 blockNum);
		return dir[blockNum].getDirStats;
	endmethod
	
endmodule
