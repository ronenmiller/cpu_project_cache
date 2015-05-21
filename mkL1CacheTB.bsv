import mkL1Cache::*;
import ProjectTypes::*;
import Randomizable :: * ;

//typedef 1 NumCPU; 
typedef enum {Start, Run, Finish, Print} State deriving (Bits, Eq);

// This TB is for 2 CPU

(* synthesize *)
module mkL1CacheTB();
	Reg#(State) state <- mkReg(Start);
	Reg#(Bit#(1)) finish <- mkReg(0);
	Reg#(Bit#(10)) cycle <- mkReg(0);
	Reg#(Bit#(10)) numReq <- mkReg(0);
	Reg#(Bool) initialized <- mkReg(False);
	Randomize#(Bit#(BlockSz)) rand32 <- mkGenericRandomizer;
	
	Reg#(Bit#(1)) isL1Req <- mkReg(0);
	
	L1Cache l1 <- mkL1Cache();
	
	//rule checkStart
	rule checkStart(state == Start);
		state <= Run;
	endrule
	
	// rule init
	rule init (!initialized);
	    rand32.cntrl.init(); 
	    initialized <= True; 
	    //print cache
	    $display("INIT-start");
	    for (Integer i=0 ; i<valueOf(RowsL1); i=i+1) begin
			for (Integer j=0 ; j<valueOf(WaysL1); j=j+1) begin			
				let data <- l1.getCellData(fromInteger(i),fromInteger(j));
				let status <- l1.getCellState(fromInteger(i),fromInteger(j));
				let tag <- l1.getCellTag(fromInteger(i),fromInteger(j));
				$display("block in row %d way %d is :\n data - %h ;\n state - %b ;\n tag - %h",i,j,data,status,tag);
			end
		end
		$display("INIT-end");
	endrule
	
	//rule countCyc - count the number of cycles
	rule countCyc(state == Run);
		cycle <= cycle+1;
		$display("##Cycle: %d##",cycle);
		
		if (cycle == 30) begin
			state <= Finish;
		end
	endrule

	// L2 gets request from L1
	rule getL1Req(state == Run && isL1Req == 0);
		L1ToL2CacheReq r <- l1.l1Reql2;
		$display("TB> got L1 request for address 0x%h",r.addr);
		isL1Req <= 1;
		//MemResp resp <- rand32.next;
	endrule
	
	// L2 sends response to L1
	rule l2Resp(state == Run && isL1Req == 1);
		BlockData resp <- rand32.next;
		$display("TB> sending L2 response with data 0x%h",resp);
		l1.l2respl1(resp);
		isL1Req <= 0;
	endrule

	// deq L1 to CPU response
	rule deqResp(state == Run);
		let resp = l1.resp;
		$display("TB> Response from L1 to CPU is: 0x%h",resp);
	endrule
	
	// L1 sends response to L2 for GM/InvGM
	rule l1RespGMInvGM(state == Run);
		BlockData resp <- l1.l1GetModified;
		$display("TB> Response from L1 to L2 is: 0x%h",resp);
	endrule
	
	// finish
	rule checkFinished(state == Finish);
		$display("Finish");
		//print cache
		$display("Finish-start");
		for (Integer i=0 ; i<valueOf(RowsL1); i=i+1) begin
			for (Integer j=0 ; j<valueOf(WaysL1); j=j+1) begin			
				let data <- l1.getCellData(fromInteger(i),fromInteger(j));
				let status <- l1.getCellState(fromInteger(i),fromInteger(j));
				let tag <- l1.getCellTag(fromInteger(i),fromInteger(j));
				$display("block in row %d way %d is :\n data - %h ;\n state - %b ;\n tag - %h",i,j,data,status,tag);
			end
		end
		$display("Finish-end");
		$finish;
  	endrule	
  		
///////////////////////////////////////////////////////////////////////////	
	//test #1
	
	//objectives: 1. test insertion of new data into the L1 cache with Wr, Rd
	//				a. when the set is not full, place in the next empty way 
	//				b. when the set is full, according to the replacement policy
	//			 2. test Wr operation - is the word written to the block 
	//				a. when the block is in the L1 cache
	//				b. when the block is not in the L1 cache or is invalid
	//			 3. test Rd operation - check response to the CPU
	//				a. when the block is in the L1 cache 
	//				b. when the block is not in the L1 cache or is invalid
	//			 4. test the interface (request and response) with L2 for block not found in the L1 cache
	//			 5. test the case a block is discarded from L1 cache and then asked for by CPU
	
	/*rule sendCPUReq0(state == Run && numReq == 0); //objective: 1a, 2b, 4
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'h19E4; //offset is 1 , index is 1 , tag is 67 (hex)
		r.data = 32'h1;
		l1.req(r);
		numReq <= numReq+1;
		//write should change word #1 to 32'h1 
	endrule
	
	rule sendCPUReq1(state == Run && numReq == 1); //objective: 2a
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'h19EC; //offset is 3 , index is 1 , tag is 67 (hex)
		r.data = 32'h3;
		l1.req(r);
		numReq <= numReq+1;
		//write should change word #3 to 32'h3
	endrule
	
	rule sendCPUReq2(state == Run && numReq == 2); //objective: 3a
		CPUToL1CacheReq r;
		r.op = Rd;
		r.addr = 32'h19E4; //offset is 1 , index is 1 , tag is 67 (hex)
		r.data = ?;
		l1.req(r);
		numReq <= numReq+1;
		//read should return 32'h1 (was written in sendCPUReq0)
	endrule
	
	rule sendCPUReq3(state == Run && numReq == 3); //objective: 1a, 3b, 5
		CPUToL1CacheReq r;
		r.op = Rd;
		r.addr = 32'h18E0; //offset is 0 , index is 1 , tag is 63 (hex)
		r.data = ?;
		l1.req(r);
		numReq <= numReq+1;
		//read should return word #0 (32 LSB of the dataBlock)
	endrule
	
	rule sendCPUReq4(state == Run && numReq == 4); //objective: 1b, 2b, 5
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'h10EC; //offset is 3 , index is 1 , tag is 43 (hex)
		r.data = 32'h4;
		l1.req(r);
		numReq <= numReq+1;
		//write should change word #3 to 32'h4
	endrule
	
	rule sendCPUReq5(state == Run && numReq == 5); //objective: 1b, 3b, 5
		CPUToL1CacheReq r;
		r.op = Rd;
		r.addr = 32'h19E4; //offset is 1 , index is 1 , tag is 67 (hex)
		r.data = ?;
		l1.req(r);
		numReq <= numReq+1;
		//read should return 32'h1 (was written in sendCPUReq0)
	endrule	*/
	
///////////////////////////////////////////////////////////////////////////
	//test #2
	//objective: 6. test the interface (request and response) with L2 when L2 asks for:
	//				a. Invalidate
	//				b. Get Modified
	//				c. Invalidate+Get Modified	
	
	
	rule sendCPUReq0(state == Run && numReq == 0);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'h19E4; //offset is 1 , index is 1 , tag is 67 (hex)
		r.data = 32'h1;
		l1.req(r);
		numReq <= numReq+1;
		//write should change word #1 to 32'h1 
	endrule
	
	rule sendCPUReq1(state == Run && numReq == 1);
		CPUToL1CacheReq r;
		r.op = Wr;
		r.addr = 32'h18E0; //offset is 0 , index is 1 , tag is 63 (hex)
		r.data = 32'h2;
		l1.req(r);
		numReq <= numReq+1;
		//write should change word #0 to 32'h2 
	endrule
	
	rule sendCPUReq2(state == Run && numReq == 2);
		L2ReqToL1 r;
		r.addr = 32'h18E0;
		r.reqType = Inv;
		l1.l1ChangeInvGM(r);
		$display("TB> L2 sending request %b with addr 0x%h",r.reqType, r.addr);
		numReq <= numReq+1;
	endrule
	
	rule sendCPUReq3(state == Run && numReq == 3);
		L2ReqToL1 r;
		r.addr = 32'h19E4;
		r.reqType = GM;
		l1.l1ChangeInvGM(r);
		$display("TB> L2 sending request %b with addr 0x%h",r.reqType, r.addr);
		numReq <= numReq+1;
	endrule
	
	rule sendCPUReq4(state == Run && numReq == 4); 
		CPUToL1CacheReq r;
		r.op = Rd;
		r.addr = 32'h10EC; //offset is 3 , index is 1 , tag is 43 (hex)
		r.data = ?;
		l1.req(r);
		numReq <= numReq+1;
		//read should return word #3
	endrule
	
	rule sendCPUReq5(state == Run && numReq == 5);
		L2ReqToL1 r;
		r.addr = 32'h10EC;
		r.reqType = InvGM;
		l1.l1ChangeInvGM(r);
		$display("TB> L2 sending request %b with addr 0x%h",r.reqType, r.addr);
		numReq <= numReq+1;
	endrule

endmodule
