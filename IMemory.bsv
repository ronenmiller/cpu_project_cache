import ProjectTypes::*;
import RegFile::*;

interface IMemory;
    method IMemResp req(Addr a);
endinterface

(* synthesize *)
module mkIMemory(IMemory);
    RegFile#(Bit#(26), Data) mem <- mkRegFileFullLoad("memory.vmh");

    method IMemResp req(Addr a);
        return mem.sub(truncate(a>>2));
    endmethod
endmodule

