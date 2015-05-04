/***************************
	Test Bench to check 
	correctnes of Directory 
	logic functionality.
****************************/

import mkDirectory::*;
import ProjectTypes::*;

typedef enum {Start, Run, Finish} State deriving (Bits, Eq);
typedef 3 NumCPU3;
typedef TypeDirReq#(NumCPU3) Req3;



(* synthesize *)
module mkDirectoryTB();
	Reg#(State) state <- mkReg(Start);
	Reg#(Bit#(1)) finish <- mkReg(0);
	Reg#(Bit#(10)) cycle <- mkReg(0);
	// This TB is built for 3 CPUs
	Directory#(NumCPU3,BlocksL2) dir <- mkDirectory();

	
	rule checkStart(state == Start);
		state <= Run;
	endrule
	
	
	rule countcyc(state == Run);
		cycle <= cycle+1;
		$display("Cycle: %d",cycle);
		
		if (cycle == 10) begin
			state <= Finish;
		end
	endrule
	/***************************************************************************************
		Test case 1 - block 0 transitions: 
			1) Load request of block 0 by two processors (0,2), state should transit 
			from Invalid to shared on first request and then remain. (first two cycles).
			2) Store request by third processor (1), state should transit from 
			shared to modified and invVec should be 101.
			3) Store request by an other processor (2), state should remain modified.
			isModified == True, invVec should be 010. modified should be 010.
			4) Store request from same processor(2),isModified == True, state should remain
			modified. invVec should be 000, modifier 100.
			5) Load request by an other processor (1). state should transit to shared.
			isModified == True, invVec = 000, modifier = 100.
			6) Store request from non present processor (0). state should transit to 
			modified. isModified == False, modifier = 000, invVec 110.
			7) Write-Back request, isModified == true, state should transit to invalid.
			modifier = 001, invVec = 001.
	****************************************************************************************/
	
	// Load request of block 0 by proc 0.
	rule dir_test1(cycle == 1);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:Rd,proc:3'b001,dest:?});
		$display("reply: blockNum - 0 reqType - Rd proc - 0 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Invalid || rep.nState != Shared || rep.invVec != 0 || rep.reqType != None) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	
	// Load request of block 0 by proc 2.
	rule dir_test2(cycle == 2);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:Rd,proc:3'b100,dest:?});
		$display("reply: blockNum - 0 reqType - Rd proc - 2 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Shared || rep.nState != Shared || rep.invVec != 0 || rep.reqType != None) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	// Store request by proc 1.	
	rule dir_test3(cycle == 3);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:Wr,proc:3'b010,dest:?});
		$display("reply: blockNum - 0 reqType - Wr proc - 1 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Shared || rep.nState != Modified || rep.invVec != 3'b101 || rep.reqType != Inv) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	
	// Store request by proc 2.
	rule dir_test4(cycle == 4);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:Wr,proc:3'b100,dest:?});
		$display("reply: blockNum - 0 reqType - Wr proc - 2 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Modified || rep.nState != Modified || rep.invVec != 3'b010 || rep.reqType != InvGM) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	// Load request by proc 1.
	rule dir_test5(cycle == 5);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:Rd,proc:3'b010,dest:?});
		$display("reply: blockNum - 0 reqType - Rd proc - 1 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Modified || rep.nState != Shared || rep.invVec != 3'b100 || rep.reqType != GM) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	// Store request by proc 0.
	rule dir_test6(cycle == 6);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:Wr,proc:3'b001,dest:?});
		$display("reply: blockNum - 0 reqType - Wr proc - 0 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Shared || rep.nState != Modified || rep.invVec != 3'b110 || rep.reqType != Inv) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	// Write-back request for block 0 by proc 0.
	rule dir_test7(cycle == 7);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:WB,proc:3'b001,dest:DestL2});
		$display("reply: blockNum - 0 reqType - WB proc - 0 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Modified || rep.nState != Shared || rep.invVec != 3'b000 || rep.reqType != None) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	// Rd request for block 0 by proc 2.
	rule dir_test8(cycle == 8);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:Wr,proc:3'b100,dest:?});
		$display("reply: blockNum - 0 reqType - Wr proc - 2 pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Shared || rep.nState != Modified || rep.invVec != 3'b000 || rep.reqType != Inv) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	// WB to Mem by L2 of block 0.
	rule dir_test9(cycle == 9);
		let rep <- dir.requestBlock(Req3{blockNum:0,op:WB,proc:3'b010,dest:DestMem});
		$display("reply: blockNum - 0 reqType - WB proc - DC pState - %d nState - %d InvVec - %b reqType - %b", rep.pState,rep.nState, rep.invVec, rep.reqType);
		if (rep.pState != Modified || rep.nState != Invalid || rep.invVec != 3'b100 || rep.reqType != Inv) begin
			$display("Error Cycle %d values do not match!",cycle);
			$finish;
		end
	endrule
	
	/***********************************************
		End Test case 1
	***********************************************/
	rule view_TB_state;
		$display("State: %d", state);
	endrule
	
  	rule checkFinished(state == Finish);
		$display("Finish");
		$finish;
  	endrule
endmodule
