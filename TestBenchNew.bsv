
import onecyc::*;
import ProjectTypes::*;

typedef 4 NumCPU; 
typedef enum {Start, Run, Finish} State deriving (Bits, Eq);

(* synthesize *)
module mkTestBench();
  Reg#(Bit#(32)) cycle <- mkReg(0);
  Reg#(State)    state <- mkReg(Start);
  
  //TODO: 
  CacheProj#(NumCPU) cache <- mkProject;
  Memory memory            <- mkProjMemory;

  Vector#(NumCPU, Proc) cpuVec <- mkProc;
 
  rule start(state == Start);
    proc.hostToCpu(32'h1000);
    state <= Run;
  endrule

  rule proc
    //rule countCyc - count the number of cycles
	rule countCyc(state == Run);
		cycle <= cycle+1;
		$display("\n##Cycle: %d##",cycle);
		if (cycle == 10) begin
			state <= Finish;
		end
	endrule
  // rule run(state == Run);
    // cycle <= cycle + 1;
    // $display("\ncycle %d", cycle);
  // endrule

  rule checkFinished(state == Run);
    let c <- proc.cpuToHost;
    $display("\n--------------------------------------------\n");
    if(tpl_1(c) == 21)
    begin
	if (tpl_2(c) == 0)
	begin
	    $display("PASSED\n");
    	end
	else
	begin
      	$display("FAILED %d\n", c);
	end
	$finish;
    end
  endrule
  

	
endmodule

