// cache types
import Vector::*;
typedef 32 AddrSz;
typedef 4 RowsL2;
typedef 2 WaysL2;
typedef Bit#(TLog#(WaysL2)) WayL2;// deriving(Eq,Bits);
typedef Bit#(AddrSz) Addr;
typedef Bit#(TLog#(RowsL2)) IndexL2;// deriving(Eq,Bits);
typedef TAdd#(2,TLog#(Words)) OffsetSz;
typedef Bit#(OffsetSz) Offset;// deriving(Eq,Bits);
typedef Bit#(TSub#(AddrSz, TAdd#(TLog#(RowsL2), OffsetSz))) TagL2; // [Tag;Index;Offset]
typedef 32 DataSz;
typedef Bit#(DataSz) Data; // word
typedef 8 Words; // words in single block
typedef TMul#(Words,DataSz) BlockSz;
typedef Bit#(BlockSz) BlockData;
typedef TMul#(RowsL2,WaysL2) BlocksL2;
typedef Bit#(TLog#(BlocksL2)) BlockNumL2;
typedef TDiv#(DataSz, 8) NumBytes;
typedef Vector#(NumBytes, Bool) ByteEn;

typedef Data Line;

typedef BlockData MemResp;

typedef enum{Ld, St} MemOp deriving(Eq,Bits);
typedef enum {Ready, FillReq, FillResp, FillHit, WrBack, GetModified} CacheStatus deriving (Bits, Eq);

typedef struct{
	IndexL2 	idx;
	WayL2		way;
	Offset  offset;
} BlockLocationL2 deriving(Eq,Bits);

typedef enum{Rd, Wr, WB, Inv} CacheOp deriving(Eq,Bits);
typedef enum{Shared,Modified,Invalid} StateType deriving (Bits, Eq);

typedef struct{
    CacheOp op;
    Addr  addr;
    BlockData  data;
    Bit#(numCPU) proc; // the requesting processor
} CacheReq#(numeric type numCPU) deriving(Eq,Bits); 

// memory types
typedef struct{
    MemOp op;
    ByteEn byteEn;
    Addr  addr;
    BlockData  data;
} MemReq deriving(Eq,Bits);

typedef enum{Inv,GM,InvGM,None} L2ReqL1 deriving (Bits, Eq);


// TODO: remove
// dir stats 
typedef struct{
	Bit#(numCPU) present;
	StateType state;
} TypeDirStats#(numeric type numCPU) deriving(Eq,Bits);


typedef struct{
	Bit#(numCPU) proc;
	Addr		 addr;
	L2ReqL1		 reqType;
} L2ToNWCacheReq#(numeric type numCPU) deriving(Eq,Bits);

