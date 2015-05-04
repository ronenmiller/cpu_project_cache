import mkProject::*;

typedef 3 NumCPU; 
typedef enum {Start, Run, Finish, Print} State deriving (Bits, Eq);

(* synthesize *)
module mkProjectTB();
	Reg#(State) state <- mkReg(Start);
	Reg#(Bit#(1)) finish <- mkReg(0);
	Reg#(Bit#(10)) cycle <- mkReg(0);
	
	Reg#(Bit#(1)) isL1Req <- mkReg(0);
	
	Project#(NumCPU) p <- mkProject();
	
	//rule checkStart
	rule checkStart(state == Start);
		state <= Run;
	endrule
	
	//rule countCyc - count the number of cycles
	rule countCyc(state == Run);
		cycle <= cycle+1;
		$display("##Cycle: %d##",cycle);
		
		if (cycle == 10) begin
			state <= Finish;
		end
	endrule


	
	// finish
	rule checkFinished(state == Finish);
		$display("Finish");
	endrule

endmodule
