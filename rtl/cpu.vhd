library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;    

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all; 

use work.pexport.all;

entity cpu is
   port 
   (
      clk1x                 : in  std_logic;
      clk2x                 : in  std_logic;
      ce                    : in  std_logic;
      reset                 : in  std_logic;
      
      irqRequest            : in  std_logic;
      
      mem_request           : out std_logic;
      mem_rnw               : out std_logic; 
      mem_isData            : out std_logic; 
      mem_isCache           : out std_logic; 
      mem_addressInstr      : out unsigned(31 downto 0); 
      mem_addressData       : out unsigned(31 downto 0); 
      mem_reqsize           : out unsigned(1 downto 0); 
      mem_writeMask         : out std_logic_vector(3 downto 0); 
      mem_dataWrite         : out std_logic_vector(31 downto 0); 
      mem_dataRead          : in  std_logic_vector(31 downto 0); 
      mem_dataCache         : in  std_logic_vector(127 downto 0);
      mem_done              : in  std_logic;
      
      gte_busy              : in  std_logic;
      gte_readEna           : out std_logic := '0';
      gte_readAddr          : out unsigned(5 downto 0);
      gte_readData          : in  unsigned(31 downto 0);
      gte_writeAddr         : out unsigned(5 downto 0);
      gte_writeData         : out unsigned(31 downto 0);
      gte_writeEna          : out std_logic := '0'; 
      gte_cmdData           : out unsigned(31 downto 0);
      gte_cmdEna            : out std_logic := '0'; 
   
      cpu_done              : out std_logic := '0'; 
      cpu_export            : out cpu_export_type := ((others => (others => '0')), (others => '0'), (others => '0'), (others => '0'))
   );
end entity;

architecture arch of cpu is
     
   -- regs
   type tRegs is array(0 to 31) of unsigned(31 downto 0);
   signal regs                         : tRegs := (others => (others => '0'));
   signal PC                           : unsigned(31 downto 0) := (others => '0');
   signal hi                           : unsigned(31 downto 0) := (others => '0');
   signal lo                           : unsigned(31 downto 0) := (others => '0');
               
   signal cop0_BPC                     : unsigned(31 downto 0) := (others => '0');
   signal cop0_BDA                     : unsigned(31 downto 0) := (others => '0');
   signal cop0_JUMPDEST                : unsigned(31 downto 0) := (others => '0');
   signal cop0_DCIC                    : unsigned(31 downto 0) := (others => '0');
   signal cop0_BADVADDR                : unsigned(31 downto 0) := (others => '0');
   signal cop0_BDAM                    : unsigned(31 downto 0) := (others => '0');
   signal cop0_BPCM                    : unsigned(31 downto 0) := (others => '0');
   signal cop0_SR                      : unsigned(31 downto 0) := (others => '0');
   signal cop0_CAUSE                   : unsigned(31 downto 0) := (others => '0');
   signal cop0_EPC                     : unsigned(31 downto 0) := (others => '0');
   signal cop0_PRID                    : unsigned(31 downto 0) := (others => '0');
         
   signal CACHECONTROL                 : unsigned(31 downto 0) := (others => '0');
               
   -- common   
   signal ce_1                         : std_logic := '0';
   
   signal stallNew1                    : std_logic := '0';
   signal stallNew2                    : std_logic := '0';
   signal stallNew3                    : std_logic := '0';
   signal stallNew4                    : std_logic := '0';
   signal stallNew5                    : std_logic := '0';
               
   signal stall1                       : std_logic := '0';
   signal stall2                       : std_logic := '0';
   signal stall3                       : std_logic := '0';
   signal stall4                       : std_logic := '0';
   signal stall5                       : std_logic := '0';
   signal stall                        : unsigned(4 downto 0) := (others => '0');
                     
   signal exception                    : unsigned(4 downto 0) := (others => '0');
               
   signal exceptionNew1                : std_logic := '0';
   signal exceptionNew3                : std_logic := '0';
   signal exceptionNew5                : std_logic := '0';
   signal exceptionNew                 : unsigned(4 downto 0) := (others => '0');
   
   signal exception_SR                 : unsigned(31 downto 0) := (others => '0');
   signal exception_CAUSE              : unsigned(31 downto 0) := (others => '0');
   signal exception_EPC                : unsigned(31 downto 0) := (others => '0');
   signal exception_JMP                : unsigned(31 downto 0) := (others => '0');
   
   signal exceptionCode                : unsigned(3 downto 0);
   signal exceptionCode_3              : unsigned(3 downto 0);   
   signal exceptionInstr               : unsigned(1 downto 0);
   signal exception_PC                 : unsigned(31 downto 0);
   signal exception_branch             : std_logic;
   signal exception_brslot             : std_logic;
   signal exception_JMPnext            : unsigned(31 downto 0);
               
   signal memoryMuxStage               : integer range 1 to 4;
               
   signal opcode0                      : unsigned(31 downto 0) := (others => '0');
   signal opcode1                      : unsigned(31 downto 0) := (others => '0');
   signal opcode2                      : unsigned(31 downto 0) := (others => '0');
   signal opcode3                      : unsigned(31 downto 0) := (others => '0');
   signal opcode4                      : unsigned(31 downto 0) := (others => '0');
               
   signal PCold0                       : unsigned(31 downto 0) := (others => '0');
   signal PCold1                       : unsigned(31 downto 0) := (others => '0');
   signal PCold2                       : unsigned(31 downto 0) := (others => '0');
   signal PCold3                       : unsigned(31 downto 0) := (others => '0');
   signal PCold4                       : unsigned(31 downto 0) := (others => '0');
         
   signal value1                       : unsigned(31 downto 0) := (others => '0');
   signal value2                       : unsigned(31 downto 0) := (others => '0');
               
   -- stage 1          
   -- cache
   signal tag_address_a                : std_logic_vector(7 downto 0);
   signal tag_data_a                   : std_logic_vector(16 downto 0);
   signal tag_wren_a                   : std_logic;
   signal tag_address_b                : std_logic_vector(7 downto 0);
   signal tag_q_b                      : std_logic_vector(16 downto 0);
   
   signal tagValid                     : std_logic_vector(0 to 255) := (others => '0');
   
   signal cache_address_a              : std_logic_vector(7 downto 0);
   signal cache_data_a                 : std_logic_vector(127 downto 0);
   signal cache_wren_a                 : std_logic_vector(0 to 3);
   signal cache_address_b              : std_logic_vector(7 downto 0);
   signal cache_q_b                    : std_logic_vector(127 downto 0);
   
   signal FetchAddr                    : unsigned(31 downto 0) := (others => '0'); 
   signal FetchLastAddr                : unsigned(31 downto 0) := (others => '0'); 
   
   signal cacheValueLast               : unsigned(31 downto 0) := (others => '0'); 
   signal cacheHitLast                 : std_logic := '0';
   
   -- regs           
   signal blockIRQ                     : std_logic := '0';
   signal blockIRQCnt                  : integer range 0 to 10;
   signal fetchReady                   : std_logic := '0';
   signal cacheHit                     : std_logic := '0';
   signal cacheUpdate                  : std_logic := '0';
               
   -- wires          
   signal mem1_request                 : std_logic := '0';
   signal mem1_cacherequest            : std_logic := '0';
   signal mem1_address                 : unsigned(31 downto 0) := (others => '0'); 
               
   signal requestStall                 : std_logic := '0';
   signal PCnext                       : unsigned(31 downto 0) := (others => '0');
   signal opcodeNext                   : unsigned(31 downto 0) := (others => '0');
   signal fetchReadyNext               : std_logic := '0';
   signal cacheHitNext                 : std_logic := '0';
   signal cacheUpdateNext              : std_logic := '0';
   signal blockIRQNext                 : std_logic := '0';
   signal blockIRQCntNext              : integer range 0 to 10;
            
   -- stage 2           
   --regs            
   signal decodeException              : std_logic := '0';
   signal decodeImmData                : unsigned(15 downto 0) := (others => '0');
   signal decodeSource1                : unsigned(4 downto 0) := (others => '0');
   signal decodeSource2                : unsigned(4 downto 0) := (others => '0');
   signal decodeValue1                 : unsigned(31 downto 0) := (others => '0');
   signal decodeValue2                 : unsigned(31 downto 0) := (others => '0');
   signal decodeOP                     : unsigned(5 downto 0) := (others => '0');
   signal decodeFunct                  : unsigned(5 downto 0) := (others => '0');
   signal decodeShamt                  : unsigned(4 downto 0) := (others => '0');
   signal decodeRD                     : unsigned(4 downto 0) := (others => '0');
   signal decodeTarget                 : unsigned(4 downto 0) := (others => '0');
   signal decodeJumpTarget             : unsigned(25 downto 0) := (others => '0');
   signal decode_gte_readAddr          : unsigned(5 downto 0) := (others => '0');
   
   -- wires
   signal opcodeCacheMuxed             : unsigned(31 downto 0) := (others => '0');
            
   -- stage 3    
   type CPU_LOADTYPE is
   (
      LOADTYPE_SBYTE,
      LOADTYPE_SWORD,
      LOADTYPE_LEFT,
      LOADTYPE_DWORD,
      LOADTYPE_BYTE,
      LOADTYPE_WORD,
      LOADTYPE_RIGHT
   );
   
   type CPU_EXESTALLTYPE is
   (
      EXESTALLTYPE_NONE,
      EXESTALLTYPE_READLO,
      EXESTALLTYPE_READHI,
      EXESTALLTYPE_GTE
   );
   
   --regs         
   signal blockLoadforward             : std_logic := '0';
   signal executeException             : std_logic := '0';
   signal resultWriteEnable            : std_logic := '0';
   signal executeGTEReadEnable         : std_logic := '0';
   signal executeBranchdelaySlot       : std_logic := '0';
   signal executeBranchTaken           : std_logic := '0';
   signal resultTarget                 : unsigned(4 downto 0) := (others => '0');
   signal resultData                   : unsigned(31 downto 0) := (others => '0');
   signal executeMemWriteEnable        : std_logic;
   signal executeMemWriteData          : unsigned(31 downto 0) := (others => '0');
   signal executeMemWriteMask          : std_logic_vector(3 downto 0) := (others => '0');
   signal executeMemWriteAddr          : unsigned(31 downto 0) := (others => '0');
   signal executeCOP0WriteEnable       : std_logic := '0';
   signal executeCOP0WriteDestination  : unsigned(4 downto 0) := (others => '0');
   signal executeCOP0WriteValue        : unsigned(31 downto 0) := (others => '0');
   signal executeLoadType              : CPU_LOADTYPE;
   signal executeReadAddress           : unsigned(31 downto 0) := (others => '0');
   signal executeReadEnable            : std_logic := '0';
   signal executeGTETarget             : unsigned(4 downto 0) := (others => '0');
   signal hiloWait                     : integer range 0 to 38;
   signal executeStalltype             : CPU_EXESTALLTYPE;
   signal execute_gte_writeAddr        : unsigned(5 downto 0) := (others => '0');
   signal execute_gte_writeData        : unsigned(31 downto 0) := (others => '0');
   signal execute_gte_writeEna         : std_logic := '0'; 
   signal execute_gte_cmdData          : unsigned(31 downto 0);
   signal execute_gte_cmdEna           : std_logic := '0'; 

   --wires
   signal branch                       : std_logic := '0';
   signal PCbranch                     : unsigned(31 downto 0) := (others => '0');
   signal EXEresultWriteEnable         : std_logic;
   signal EXEresultData                : unsigned(31 downto 0) := (others => '0');
   signal EXEresultTarget              : unsigned(4 downto 0) := (others => '0');
   signal EXEBranchdelaySlot           : std_logic := '0';
   signal EXEBranchTaken               : std_logic := '0';
   signal EXEMemWriteEnable            : std_logic := '0';
   signal EXEMemWriteData              : unsigned(31 downto 0) := (others => '0');
   signal EXEMemWriteMask              : std_logic_vector(3 downto 0) := (others => '0');
   signal EXEMemAddr                   : unsigned(31 downto 0) := (others => '0');
   signal EXEMemWriteException         : std_logic := '0';
   signal EXECOP0WriteEnable           : std_logic := '0';
   signal EXECOP0WriteDestination      : unsigned(4 downto 0) := (others => '0');
   signal EXECOP0WriteValue            : unsigned(31 downto 0) := (others => '0');
   signal EXELoadType                  : CPU_LOADTYPE;
   signal EXEReadEnable                : std_logic := '0';
   signal EXEReadException             : std_logic := '0';
   signal EXEGTeReadEnable             : std_logic := '0';
   signal EXEcalcMULT                  : std_logic := '0';
   signal EXEcalcMULTU                 : std_logic := '0';
   signal EXEcalcDIV                   : std_logic := '0';
   signal EXEcalcDIVU                  : std_logic := '0';
   signal EXEhiUpdate                  : std_logic := '0';
   signal EXEloUpdate                  : std_logic := '0';
   signal EXEstalltype                 : CPU_EXESTALLTYPE;
   signal EXEgte_writeAddr             : unsigned(5 downto 0);
   signal EXEgte_writeData             : unsigned(31 downto 0);
   signal EXEgte_writeEna              : std_logic := '0';    
   signal EXEgte_cmdData               : unsigned(31 downto 0);
   signal EXEgte_cmdEna                : std_logic := '0'; 
   
   --MULT/DIV
   type CPU_HILOCALC is
   (
      HILOCALC_MULT, 
      HILOCALC_MULTU,
      HILOCALC_DIV,  
      HILOCALC_DIVU,
      HILOCALC_DIV0
   );
   signal hilocalc                     : CPU_HILOCALC;
   
   signal mul1                         : unsigned(31 downto 0);
   signal mul2                         : unsigned(31 downto 0);
   signal mulResultS                   : signed(63 downto 0);
   signal mulResultU                   : unsigned(63 downto 0);
   
   signal DIVstart                     : std_logic;
   signal DIVdividend                  : signed(32 downto 0);
   signal DIVdivisor                   : signed(32 downto 0);
   signal DIVquotient                  : signed(32 downto 0);
   signal DIVremainder                 : signed(32 downto 0);    
   signal DIV0quotient                 : unsigned(31 downto 0);
   signal DIV0remainder                : unsigned(31 downto 0);    
         
   -- stage 4 
   -- scratchpad
   signal scratchpad_address_a         : std_logic_vector(7 downto 0);
   signal scratchpad_data_a            : std_logic_vector(31 downto 0);
   signal scratchpad_wren_a            : std_logic_vector(3 downto 0);
   signal scratchpad_address_b         : std_logic_vector(7 downto 0);
   signal scratchpad_q_b               : std_logic_vector(31 downto 0);
   signal scratchpad_dataread          : unsigned(31 downto 0);
   
   -- reg      
   signal writebackException           : std_logic := '0';
   signal writebackTarget              : unsigned(4 downto 0) := (others => '0');
   signal writebackData                : unsigned(31 downto 0) := (others => '0');
   signal writebackWriteEnable         : std_logic := '0';
   signal writebackGTEReadEnable       : std_logic := '0';
   signal writebackMemOPisRead         : std_logic := '0';
   signal writebackLoadType            : CPU_LOADTYPE;
   signal writebackReadAddress         : unsigned(31 downto 0) := (others => '0');
   signal writebackInvalidateCacheEna  : std_logic := '0';
   signal writebackInvalidateCacheLine : unsigned(7 downto 0) := (others => '0');
   signal WBgte_writeAddr              : unsigned(5 downto 0);
         
   -- wire     
   signal mem4_request                 : std_logic := '0';
   signal mem4_address                 : unsigned(31 downto 0) := (others => '0');
   signal mem4_reqsize                 : unsigned(1 downto 0) := (others => '0');
   signal mem4_rnw                     : std_logic := '0';
   signal mem4_dataWrite               : std_logic_vector(31 downto 0) := (others => '0');
   signal WBCACHECONTROL               : unsigned(31 downto 0) := (others => '0');
   signal WBinvalidateCacheEna         : std_logic := '0';
   signal WBinvalidateCacheLine        : unsigned(7 downto 0) := (others => '0');
         
         
   -- stage 5     
   -- reg      
   signal writeDoneTarget              : unsigned(4 downto 0) := (others => '0');
   signal writeDoneData                : unsigned(31 downto 0) := (others => '0');
   signal writeDoneWriteEnable         : std_logic := '0';
   
   -- debug
   signal debugCnt                     : unsigned(31 downto 0);
   
begin 

   -- IO
   mem_request       <= mem1_request or mem4_request;
   mem_isData        <= mem4_request;
   mem_isCache       <= mem1_cacherequest;
   mem_rnw           <= mem4_rnw     when mem4_request = '1' else '1';
   mem_addressInstr  <= mem1_address;
   mem_addressData   <= mem4_address;
   mem_reqsize       <= mem4_reqsize when mem4_request = '1' else "10";
   mem_dataWrite     <= mem4_dataWrite;
   mem_writeMask     <= executeMemWriteMask;

   -- common
   stall        <= stall5 & stall4 & stall3 & stall2 & stall1;

   exceptionNew <= exceptionNew5 & '0' & exceptionNew3 & '0' & exceptionNew1;
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
         if (reset = '1') then
         
            memoryMuxStage <= 1;
         
         elsif (ce = '1') then
            
            if (mem_request = '1') then
               if (mem4_request = '1') then 
                  memoryMuxStage <= 4;
               else
                  memoryMuxStage  <= 1;
                  FetchLastAddr   <= mem1_address;
               end if;
            end if;
   
         end if;
      end if;
   end process;

--##############################################################
--############################### stage 1
--##############################################################

   itagram : altdpram
	GENERIC MAP 
   (
   	indata_aclr                         => "OFF",
      indata_reg                          => "INCLOCK",
      intended_device_family              => "Cyclone V",
      lpm_type                            => "altdpram",
      outdata_aclr                        => "OFF",
      outdata_reg                         => "UNREGISTERED",
      ram_block_type                      => "MLAB",
      rdaddress_aclr                      => "OFF",
      rdaddress_reg                       => "UNREGISTERED",
      rdcontrol_aclr                      => "OFF",
      rdcontrol_reg                       => "UNREGISTERED",
      read_during_write_mode_mixed_ports  => "CONSTRAINED_DONT_CARE",
      width                               => 17,
      widthad                             => 8,
      width_byteena                       => 1,
      wraddress_aclr                      => "OFF",
      wraddress_reg                       => "INCLOCK",
      wrcontrol_aclr                      => "OFF",
      wrcontrol_reg                       => "INCLOCK"
	)
	PORT MAP (
      inclock    => clk1x,
      wren       => tag_wren_a,
      data       => tag_data_a,
      wraddress  => tag_address_a,
      rdaddress  => tag_address_b,
      q          => tag_q_b
	);

   tag_address_a <= std_logic_vector(FetchLastAddr(11 downto 4));
   tag_data_a    <= std_logic_vector(FetchLastAddr(28 downto 12));
   
   tag_address_b <= std_logic_vector(FetchAddr(11 downto 4));

   gcache: for i in 0 to 3 generate
   begin
      icache: entity work.dpram
      generic map ( addr_width => 8, data_width => 32)
      port map
      (
         clock_a     => clk1x,
         clken_a     => ce,
         address_a   => cache_address_a,
         data_a      => cache_data_a((32*i) + 31 downto (32*i)),
         wren_a      => cache_wren_a(i),
         
         clock_b     => clk1x,
         address_b   => cache_address_b,
         data_b      => x"00000000",
         wren_b      => '0',
         q_b         => cache_q_b((32*i) + 31 downto (32*i))
      );
   end generate; 
   
   cache_address_a <= std_logic_vector(FetchLastAddr(11 downto 4));
   
   FetchAddr       <= x"BFC00180" when (exception > 0 and cop0_SR(22) = '1') else
                      x"80000080" when (exception > 0 and cop0_SR(22) = '0') else
                      PCbranch when branch = '1' else
                      PC;
                      
   cache_address_b <= std_logic_vector(FetchAddr(11 downto 4));

   mem1_address    <= FetchAddr;

   process (blockirq, cop0_SR, cop0_CAUSE, exception, stall, branch, PCbranch, mem4_request, mem_done, mem_dataRead, memoryMuxStage, PC, fetchReady, stall1, exceptionNew, opcode0, mem_dataCache, reset, FetchAddr, 
            cacheUpdate, tagValid, tag_q_b, blockirqCnt, FetchLastAddr)
      variable request : std_logic;
   begin
      request         := '0';
      PCnext          <= PC;
      fetchReadyNext  <= fetchReady;
      stallNew1       <= stall1;
      opcodeNext      <= opcode0;
      cacheUpdateNext <= '0';
      blockirqNext    <= blockirq;
      blockirqCntNext <= blockirqCnt;
      
      exceptionNew1   <= '0';
      exceptionNew5   <= '0';

      cache_data_a    <= mem_dataCache;
      cache_wren_a    <= "0000";
      tag_wren_a      <= '0';
      if (mem_done = '1' and memoryMuxStage = 1) then 
         case (to_integer(unsigned(FetchLastAddr(31 downto 29)))) is
            when 0 | 4 => -- cached
               cache_wren_a <= "1111";
               tag_wren_a   <= '1';
            when others => null;
         end case;
      end if;
      
      
      if (blockirq = '0' and cop0_SR(0) = '1' and cop0_SR(10) = '1' and cop0_CAUSE(10) = '1') then
      
         if (stall = 0) then
            blockirqNext    <= '1';
            blockirqCntNext <= 10;     
            exceptionNew5   <= '1';
         elsif (mem_done = '1') then  
            stallNew1       <= '0';
         end if;
         
      elsif (stall = 0) then
      
         if (exception > 0) then
      
            request := '1';
            if (cop0_SR(22) = '1') then
               PCnext <= x"BFC00180";
            else
               PCnext <= x"80000080";
            end if;
            
         else 
         
            if (branch = '1') then
               PCnext          <= PCbranch;
            end if;
            
            fetchReadyNext <= '0';
            
            if (mem4_request = '0') then
               request := '1';
            else
               stallNew1 <= '1';
            end if;
            
            if (blockirqCnt > 0) then
               blockirqCntNext <= blockirqCnt - 1;
               if (blockirqCnt = 1) then
                  blockirqNext <= '0';
               end if;
            end if;
      
         end if;
      
      else
      
         if (mem_done = '1' and memoryMuxStage = 1) then
            
            case (to_integer(unsigned(PC(31 downto 29)))) is
            
               when 0 | 4 => -- cached
                  cacheUpdateNext <= '1';
                  
               when 5 =>
                  stallNew1      <= '0';
                  PCnext         <= PC + 4;
                  fetchReadyNext <= '1';
                  opcodeNext <= unsigned(mem_dataRead);
               
               when others => report "should never happen" severity failure; 
               
            end case;
            
         end if;
         
         if (mem_done = '1' and memoryMuxStage = 4 and fetchReady = '0' and exception = 0) then
            request := '1';
         end if;
      
      end if;
      
      requestStall      <= '0';
      mem1_request      <= '0';
      mem1_cacherequest <= '0';
      
      cacheHitNext      <= '0';
      
      if ((cacheUpdate = '1' or request = '1') and reset = '0') then
      
         case (to_integer(unsigned(FetchAddr(31 downto 29)))) is
            
            when 0 | 4 => -- cached
               if (unsigned(tag_q_b) = FetchAddr(28 downto 12) and tagValid(to_integer(FetchAddr(11 downto 4))) = '1') then
                  cacheHitNext      <= '1';
                  stallNew1         <= '0';
                  PCnext            <= FetchAddr + 4;
               else
                  mem1_request      <= '1';
                  requestStall      <= '1';
                  mem1_cacherequest <= '1';
               end if;
               
            when 5 =>
               mem1_request      <= '1';
               requestStall      <= '1';
               mem1_cacherequest <= '0';
            
            when others =>
               -- todo
            
         end case;
      
      end if;
      
   end process;
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
         
         ce_1 <= ce;
      
         if (reset = '1') then
         
            tagValid      <= (others => '0');
         
            stall1        <= '0';
            PC            <= x"BFC00000";
                        
            blockIRQ      <= '0';
            fetchReady    <= '0';
            opcode0       <= (others => '0');
            PCold0        <= (others => '0');
            
            cacheHit      <= '0';
            cacheUpdate   <= '0';
            cacheHitLast  <= '0';
         
         elsif (ce = '1') then
            
            fetchReady     <= fetchReadyNext;
            PC             <= PCnext;
            stall1         <= stallNew1 or requestStall;
            
            blockirq       <= blockirqNext;   
            blockirqCnt    <= blockirqCntNext;
            
            cacheHit       <= cacheHitNext;
            cacheUpdate    <= cacheUpdateNext;
            if (cacheHit = '1' and stall > 0) then
               cacheHitLast   <= '1';
               case (PCold0(3 downto 2)) is
                  when "00" => cacheValueLast <= unsigned(cache_q_b( 31 downto  0));
                  when "01" => cacheValueLast <= unsigned(cache_q_b( 63 downto 32));
                  when "10" => cacheValueLast <= unsigned(cache_q_b( 95 downto 64));
                  when "11" => cacheValueLast <= unsigned(cache_q_b(127 downto 96));
                  when others => null;
               end case;
            elsif (stall = 0) then
               cacheHitLast <= '0';
            end if;
            
            if (fetchReadyNext = '1') then
               opcode0 <= opcodeNext; 
               PCold0  <= PC;
            end if;
            
            if (cacheHitNext = '1') then
               PCold0 <= FetchAddr;
            end if;
   
            if (mem_done = '1' and memoryMuxStage = 1) then 
               case (to_integer(unsigned(PC(31 downto 29)))) is
                  when 0 | 4 => -- cached
                     tagValid(to_integer(PC(11 downto 4))) <= '1';
                  when others => null;
               end case;
            end if;
            
            if (writebackInvalidateCacheEna = '1') then
               tagValid(to_integer(writebackInvalidateCacheLine)) <= '0';
            end if;
            
         elsif (ce_1 = '1') then
            
            if (cacheHit = '1') then
               cacheHitLast   <= '1';
               case (PCold0(3 downto 2)) is
                  when "00" => cacheValueLast <= unsigned(cache_q_b( 31 downto  0));
                  when "01" => cacheValueLast <= unsigned(cache_q_b( 63 downto 32));
                  when "10" => cacheValueLast <= unsigned(cache_q_b( 95 downto 64));
                  when "11" => cacheValueLast <= unsigned(cache_q_b(127 downto 96));
                  when others => null;
               end case;
            end if;
               
         end if;
      end if;
     
   end process;
   
   
--##############################################################
--############################### stage 2
--##############################################################
   
   opcodeCacheMuxed <= cacheValueLast when cacheHitLast = '1' else
                       unsigned(cache_q_b( 31 downto  0)) when (cacheHit = '1' and PCold0(3 downto 2) = "00") else
                       unsigned(cache_q_b( 63 downto 32)) when (cacheHit = '1' and PCold0(3 downto 2) = "01") else
                       unsigned(cache_q_b( 95 downto 64)) when (cacheHit = '1' and PCold0(3 downto 2) = "10") else
                       unsigned(cache_q_b(127 downto 96)) when (cacheHit = '1' and PCold0(3 downto 2) = "11") else
                       opcode0;

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
         if (reset = '1') then
         
            stall2     <= '0';
            
            pcOld1  <= (others => '0');
            opcode1 <= (others => '0');
            
            decodeException  <= '0';
            decodeImmData    <= (others => '0');
            decodeSource1    <= (others => '0');
            decodeSource2    <= (others => '0');
            decodeValue1     <= (others => '0');
            decodeValue2     <= (others => '0');
            decodeOP         <= (others => '0');
            decodeFunct      <= (others => '0');
            decodeShamt      <= (others => '0');
            decodeRD         <= (others => '0');
            decodeTarget     <= (others => '0');
            decodeJumpTarget <= (others => '0');
         
         elsif (ce = '1') then
            
            if (stall = 0) then
            
               if (exception(4 downto 1) > 0) then
               
                  if (exception(4) = '1') then decodeException <= '1'; end if;
                  
                  decodeImmData    <= (others => '0');
                  decodeSource1    <= (others => '0');
                  decodeSource2    <= (others => '0');
                  decodeValue1     <= (others => '0');
                  decodeValue2     <= (others => '0');
                  decodeOP         <= (others => '0');
                  decodeFunct      <= (others => '0');
                  decodeShamt      <= (others => '0');
                  decodeRD         <= (others => '0');
                  decodeTarget     <= (others => '0');
                  decodeJumpTarget <= (others => '0');
               
               else
               
                  decodeException <= '0';
                  if (exception(0) = '1') then decodeException <= '1'; end if;
   
                  pcOld1  <= pcOld0;
                  opcode1 <= opcodeCacheMuxed;
   
                  decodeImmData    <= opcodeCacheMuxed(15 downto 0);
                  decodeJumpTarget <= opcodeCacheMuxed(25 downto 0);
                  decodeSource1    <= opcodeCacheMuxed(25 downto 21);
                  decodeSource2    <= opcodeCacheMuxed(20 downto 16);
                  decodeValue1     <= regs(to_integer(opcodeCacheMuxed(25 downto 21)));
                  decodeValue2     <= regs(to_integer(opcodeCacheMuxed(20 downto 16)));
                  decodeOP         <= opcodeCacheMuxed(31 downto 26);
                  decodeFunct      <= opcodeCacheMuxed(5 downto 0);
                  decodeShamt      <= opcodeCacheMuxed(10 downto 6);
                  decodeRD         <= opcodeCacheMuxed(15 downto 11);
                  if (opcodeCacheMuxed(31 downto 26) > 0) then
                     decodeTarget  <= opcodeCacheMuxed(20 downto 16);
                  else
                     decodeTarget  <= opcodeCacheMuxed(15 downto 11);
                  end if;
                                     
                  if (opcodeCacheMuxed(31 downto 26) = 16#12#) then
                     decode_gte_readAddr <= opcodeCacheMuxed(22) & opcodeCacheMuxed(15 downto 11); -- decodeSource1(1) & decodeRD 
                  else
                     decode_gte_readAddr <= '0' & opcodeCacheMuxed(20 downto 16); -- decodeSource2
                  end if;
                  
               end if;
      
            end if;
            
         end if;
      end if;
   end process;
   
   
--##############################################################
--############################### stage 3
--##############################################################

   process (decodeValue1, decodeValue2, decodeSource1, decodeSource2, resultTarget, writebackTarget, writeDoneTarget, resultWriteEnable, writebackWriteEnable, writeDoneWriteEnable, resultData, writebackData, writeDoneData, blockLoadforward)
   begin
   
      value1 <= decodeValue1;
      if    (decodeSource1 > 0 and resultTarget    = decodeSource1 and resultWriteEnable    = '1') then value1 <= resultData;
      elsif (decodeSource1 > 0 and writebackTarget = decodeSource1 and writebackWriteEnable = '1') then value1 <= writebackData;
      elsif (decodeSource1 > 0 and writeDoneTarget = decodeSource1 and writeDoneWriteEnable = '1') then value1 <= writeDoneData;
      end if;
      
      value2 <= decodeValue2;
      if    (decodeSource2 > 0 and resultTarget    = decodeSource2 and resultWriteEnable    = '1')                            then value2 <= resultData;
      elsif (decodeSource2 > 0 and writebackTarget = decodeSource2 and writebackWriteEnable = '1' and blockLoadforward = '0') then value2 <= writebackData;
      elsif (decodeSource2 > 0 and writeDoneTarget = decodeSource2 and writeDoneWriteEnable = '1')                            then value2 <= writeDoneData;
      end if;
      
   end process;

   process (decodeImmData, decodeTarget, decodeJumpTarget, decodeSource1, decodeSource2, decodeValue1, decodeValue2, decodeOP, decodeFunct, decodeShamt, decodeRD, exception, stall3, stall, value1, value2, pcOld0, resultData, executeStalltype,
            cop0_BPC, cop0_BDA, cop0_JUMPDEST, cop0_DCIC, cop0_BADVADDR, cop0_BDAM, cop0_BPCM, cop0_SR, cop0_CAUSE, cop0_EPC, cop0_PRID, PC, hi, lo, hiloWait, opcode1, gte_readAddr, decode_gte_readAddr, gte_readData, gte_busy)
      variable calcResult  : unsigned(31 downto 0);
      variable calcMemAddr : unsigned(31 downto 0);
   begin
   
      branch                  <= '0';
      exceptionNew3           <= '0';
      stallNew3               <= stall3;
      EXEresultData           <= resultData;
      PCbranch                <= pcOld0;
      EXEresultTarget         <= decodeTarget;
      EXEresultWriteEnable    <= '0';          
            
      calcMemAddr             := value1 + unsigned(resize(signed(decodeImmData), 32));
      EXEMemAddr              <= calcMemAddr;
      
      EXEMemWriteEnable       <= '0';
      EXEMemWriteData         <= value2;
      EXEMemWriteMask         <= "1111";
      EXEMemWriteException    <= '0';
      
      EXELoadType             <= LOADTYPE_DWORD;
      EXEReadEnable           <= '0';
      EXEReadException        <= '0';
      EXEGTeReadEnable        <= '0';
      
      EXECOP0WriteEnable      <= '0';
      EXECOP0WriteDestination <= decodeRD;
      EXECOP0WriteValue       <= value2;
      
      EXEBranchdelaySlot      <= '0';
      EXEBranchTaken          <= '0';
      
      EXEcalcMULT             <= '0';
      EXEcalcMULTU            <= '0';
      EXEcalcDIV              <= '0';
      EXEcalcDIVU             <= '0';
      
      EXEhiUpdate             <= '0';
      EXEloUpdate             <= '0';
      
      EXEgte_cmdEna           <= '0';
      EXEgte_cmdData          <= opcode1;
      
      EXEgte_writeAddr        <= gte_readAddr;
      EXEgte_writeData        <= value2;
      EXEgte_writeEna         <= '0';
      
      exceptionCode_3         <= x"0";
      
      EXEstalltype            <= EXESTALLTYPE_NONE;
      
      gte_readAddr            <= decode_gte_readAddr;
      gte_readEna             <= '0';
      
      if (executeStalltype = EXESTALLTYPE_GTE and gte_busy = '0') then
         gte_readEna         <= '1';
      end if;

      if (exception(4 downto 2) = 0 and stall = 0) then
             
         case (to_integer(decodeOP)) is
         
            when 16#00# =>
               case (to_integer(decodeFunct)) is
         
                  when 16#00# => -- SLL
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value2 sll to_integer(decodeShamt);
                    
                  when 16#02# => -- SRL
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value2 srl to_integer(decodeShamt);  
                  
                  when 16#03# => -- SRA
                     EXEresultWriteEnable <= '1';              
                     EXEresultData        <= unsigned(shift_right(signed(value2),to_integer(decodeShamt)));            

                  when 16#04# => -- SLLV
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value2 sll to_integer(value1(4 downto 0));        

                  when 16#06# => -- SRLV
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value2 srl to_integer(value1(4 downto 0));     

                  when 16#07# => -- SRAV
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= unsigned(shift_right(signed(value2),to_integer(value1(4 downto 0))));                        
                    
                  when 16#08# => -- JR 
                     EXEBranchdelaySlot <= '1';
                     EXEBranchTaken     <= '1';               
                     PCbranch           <= value1;
                     if (value1(1 downto 0) > 0) then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"4";
                     else
                        branch <= '1';
                     end if;
                    
                  when 16#09# => -- JALR
                     EXEBranchdelaySlot   <= '1';
                     EXEBranchTaken       <= '1';               
                     PCbranch             <= value1;
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= PC;
                     EXEresultTarget      <= decodeRD;
                     if (value1(1 downto 0) > 0) then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"4";
                     else
                        branch <= '1';
                     end if;

                  when 16#0C# => -- SYSCALL
                     exceptionNew3   <= '1';
                     exceptionCode_3 <= x"8";
                     
                  when 16#0D# => -- BREAK
                     exceptionNew3   <= '1';
                     exceptionCode_3 <= x"9";

                  when 16#10# => -- MFHI
                     EXEresultWriteEnable <= '1';
                     if (hiloWait > 0) then
                        stallNew3    <= '1';
                        EXEstalltype <= EXESTALLTYPE_READHI;
                     else
                        EXEresultData <= hi;
                     end if;
                     
                  when 16#11# => -- MTHI
                     EXEhiUpdate <= '1';
                     
                  when 16#12# => -- MFLO
                     EXEresultWriteEnable <= '1';
                     if (hiloWait > 0) then
                        stallNew3    <= '1';
                        EXEstalltype <= EXESTALLTYPE_READLO;
                     else
                        EXEresultData <= lo;
                     end if;
                     
                  when 16#13# => -- MTLO
                     EXEloUpdate <= '1';

                  when 16#18# => -- MULT
                     EXEcalcMULT <= '1';
                     
                  when 16#19# => -- MULTU
                     EXEcalcMULTU <= '1';
                     
                  when 16#1A# => -- DIV
                     EXEcalcDIV <= '1';
                     
                  when 16#1B# => -- DIVU
                     EXEcalcDIVU <= '1';
                  
                  when 16#20# => -- ADD
                     calcResult    := value1 + value2; 
                     EXEresultData <= calcResult;               
                     if (((calcResult(31) xor value1(31)) and (calcResult(31) xor value2(31))) = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"C";
                     else
                        EXEresultWriteEnable <= '1';
                     end if;

                  when 16#21# => -- ADDU
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value1 + value2;  
                    
                  when 16#22# => -- SUB
                     calcResult    := value1 - value2; 
                     EXEresultData <= calcResult;               
                     if (((calcResult(31) xor value1(31)) and (value1(31) xor value2(31))) = '1') then
                        exceptionNew3   <= '1';
                        exceptionCode_3 <= x"C";
                     else
                        EXEresultWriteEnable <= '1';
                     end if;

                  when 16#23# => -- SUBU
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value1 - value2;

                  when 16#24# => -- AND
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value1 and value2;
                    
                  when 16#25# => -- OR
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value1 or value2;
                     
                  when 16#26# => -- XOR
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value1 xor value2;
                     
                  when 16#27# => -- NOR
                     EXEresultWriteEnable <= '1';
                     EXEresultData        <= value1 nor value2;
                 
                  when 16#2A# => -- SLT
                     EXEresultWriteEnable <= '1';
                     if (signed(value1) < signed(value2)) then 
                        EXEresultData <= x"00000001";
                     else
                        EXEresultData <= x"00000000";
                     end if;  
                   
                  when 16#2B# => -- SLTI
                     EXEresultWriteEnable <= '1';
                     if (value1 < value2) then 
                        EXEresultData <= x"00000001";
                     else
                        EXEresultData <= x"00000000";
                     end if;   
                     
                  when others => 
                     exceptionNew3   <= '1';
                     exceptionCode_3 <= x"A";
                     
               end case;
               
            when 16#01# => -- B: BLTZ, BGEZ, BLTZAL, BGEZAL
               EXEBranchdelaySlot <= '1';
               if (decodeSource2(0) = '1') then
                  if (signed(value1) >= 0) then
                     EXEBranchTaken <= '1';               
                     branch         <= '1';
                  end if;
               else
                  if (signed(value1) < 0) then
                     EXEBranchTaken <= '1';               
                     branch         <= '1';
                  end if;
               end if;
               if (decodeSource2(4 downto 1) = "1000") then
                    EXEresultWriteEnable <= '1';
                    EXEresultData        <= PC;
                    EXEresultTarget      <= to_unsigned(31, 5);
               end if;
               PCbranch <= pcOld0 + unsigned((resize(signed(decodeImmData), 30) & "00"));
               
            when 16#02# => -- J
               EXEBranchdelaySlot <= '1';
               EXEBranchTaken     <= '1';               
               branch             <= '1';
               PCbranch           <= pcOld0(31 downto 28) & decodeJumpTarget & "00";
               
            when 16#03# => -- JAL
               EXEBranchdelaySlot   <= '1';
               EXEBranchTaken       <= '1';               
               branch               <= '1';
               EXEresultWriteEnable <= '1';
               EXEresultData        <= PC;
               EXEresultTarget      <= to_unsigned(31, 5);
               PCbranch             <= pcOld0(31 downto 28) & decodeJumpTarget & "00";
               
            when 16#04# => -- BEQ
               EXEBranchdelaySlot   <= '1';
               PCbranch             <= pcOld0 + unsigned((resize(signed(decodeImmData), 30) & "00"));
               if (value1 = value2) then
                  EXEBranchTaken    <= '1';               
                  branch            <= '1';
               end if;
            
            when 16#05# => -- BNE
               EXEBranchdelaySlot   <= '1';
               PCbranch             <= pcOld0 + unsigned((resize(signed(decodeImmData), 30) & "00"));
               if (value1 /= value2) then
                  EXEBranchTaken    <= '1';               
                  branch            <= '1';
               end if;
            
            when 16#06# => -- BLEZ
               EXEBranchdelaySlot   <= '1';
               PCbranch             <= pcOld0 + unsigned((resize(signed(decodeImmData), 30) & "00"));
               if (signed(value1) <= 0) then
                  EXEBranchTaken    <= '1';               
                  branch            <= '1';
               end if;
               
            when 16#07# => -- BGTZ
               EXEBranchdelaySlot   <= '1';
               PCbranch             <= pcOld0 + unsigned((resize(signed(decodeImmData), 30) & "00"));
               if (signed(value1) > 0) then
                  EXEBranchTaken    <= '1';               
                  branch            <= '1';
               end if;
            
            when 16#08# => -- ADDI
               calcResult    := value1 + unsigned(resize(signed(decodeImmData), 32)); 
               EXEresultData <= calcResult;               
               if (((calcResult(31) xor value1(31)) and (calcResult(31) xor decodeImmData(15))) = '1') then
                  exceptionNew3   <= '1';
                  exceptionCode_3 <= x"C";
               else
                  EXEresultWriteEnable <= '1';
               end if;
            
            when 16#09# => -- ADDIU
               EXEresultData        <= value1 + unsigned(resize(signed(decodeImmData), 32));            
               EXEresultWriteEnable <= '1';
               
            when 16#0A# => -- SLTI
               EXEresultWriteEnable <= '1';
               if (signed(value1) < resize(signed(decodeImmData), 32)) then 
                  EXEresultData <= x"00000001";
               else
                  EXEresultData <= x"00000000";
               end if;
               
            when 16#0B# => -- SLTIU
               EXEresultWriteEnable <= '1';
               if (value1 < unsigned(resize(signed(decodeImmData), 32))) then 
                  EXEresultData <= x"00000001";
               else
                  EXEresultData <= x"00000000";
               end if;
               
            when 16#0C# => -- ANDI
               EXEresultWriteEnable <= '1';
               EXEresultData        <= x"0000" & (value1(15 downto 0) and decodeImmData);
               
            when 16#0D# => -- ORI
               EXEresultWriteEnable <= '1';
               EXEresultData        <= value1(31 downto 16) & (value1(15 downto 0) or decodeImmData);
               
            when 16#0E# => -- XORI
               EXEresultWriteEnable <= '1';
               EXEresultData        <= value1(31 downto 16) & (value1(15 downto 0) xor decodeImmData);
               
            when 16#0F# => -- LUI
               EXEresultWriteEnable <= '1';
               EXEresultData        <= decodeImmData & x"0000";
               
            when 16#10# => -- COP0
               if (cop0_SR(1) = '1' and cop0_SR(28) = '0') then
                  exceptionNew3   <= '1';
                  exceptionCode_3 <= x"B";
               else
                  if (decodeSource1(4) = '1') then
                     case (to_integer(decodeImmData(6 downto 0))) is
                        when 1 | 2 | 4 | 8 =>
                           exceptionNew3   <= '1';
                           exceptionCode_3 <= x"A";

                        when 16 => -- Cop0Op - rfe
                           EXECOP0WriteEnable      <= '1';
                           EXECOP0WriteDestination <= to_unsigned(12, 5);
                           EXECOP0WriteValue       <= cop0_SR(31 downto 4) & cop0_SR(5 downto 2);

                        when others => report "should not happen" severity failure; 
                     end case;
                  else
                     case (to_integer(decodeSource1)) is
                     
                        when 0 => -- mfcn
                           EXEresultWriteEnable <= '1';
                           case (to_integer(decodeRD)) is
                              when 16#3# => EXEresultData <= cop0_BPC;
                              when 16#5# => EXEresultData <= cop0_BDA;
                              when 16#6# => EXEresultData <= cop0_JUMPDEST;
                              when 16#7# => EXEresultData <= cop0_DCIC;
                              when 16#8# => EXEresultData <= cop0_BADVADDR;
                              when 16#9# => EXEresultData <= cop0_BDAM;
                              when 16#B# => EXEresultData <= cop0_BPCM;
                              when 16#C# => EXEresultData <= cop0_SR;
                              when 16#D# => EXEresultData <= cop0_CAUSE;
                              when 16#E# => EXEresultData <= cop0_EPC;
                              when 16#F# => EXEresultData <= cop0_PRID;
                              when others => EXEresultData <= (others => '0');
                           end case;

                        when 4 => -- mtcn
                           exeCOP0WriteEnable      <= '1';
                           exeCOP0WriteDestination <= decodeRD;
                           exeCOP0WriteValue       <= value2;
                         
                        when others => report "should not happen" severity failure; 
                     end case;
                  end if;
               end if;
               
            when 16#11# => -- COP1 -> NOP 
               null; 
               
            when 16#12# => -- COP2
               if (cop0_SR(30) = '0') then -- COP2 disabled
                  exceptionNew3   <= '1';
                  exceptionCode_3 <= x"B";
               else
                  if (decodeSource1(4) = '1') then
                     EXEgte_cmdEna <= '1';
                  else
                     case (decodeSource1(3 downto 0)) is
                        when x"0" => --mfcn
                           EXEresultWriteEnable <= '1';
                           gte_readEna          <= '1';
                           EXEresultData        <= gte_readData;
                           if (gte_busy = '1') then
                              stallNew3    <= '1';
                              EXEstalltype <= EXESTALLTYPE_GTE;
                           end if;
                        
                        when x"2" => --cfcn
                           EXEresultWriteEnable <= '1';
                           gte_readEna          <= '1';
                           EXEresultData        <= gte_readData;
                           if (gte_busy = '1') then
                              stallNew3    <= '1';
                              EXEstalltype <= EXESTALLTYPE_GTE;
                           end if;
                        
                        when x"4" => --mtcn
                           EXEgte_writeEna      <= '1';
                        
                        when x"6" => --cfcn
                           EXEgte_writeEna      <= '1';
                        
                        when others => null;
                     end case;
                  end if;
               end if;
               
            when 16#13# => -- COP3 -> NOP 
               null; 

            when 16#20# => -- LB
               EXELoadType   <= LOADTYPE_SBYTE;
               EXEReadEnable <= '1';
               
             when 16#21# => -- LH
               EXELoadType <= LOADTYPE_SWORD;
               if (calcMemAddr(0) = '1') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if;  

            when 16#22# => -- LWL
               EXELoadType   <= LOADTYPE_LEFT;
               EXEReadEnable <= '1';
               EXEresultData <= value2;
               
            when 16#23# => -- LW
               EXELoadType <= LOADTYPE_DWORD;
               if (calcMemAddr(1 downto 0) /= "00") then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if;  

            when 16#24# => -- LBU
               EXELoadType <= LOADTYPE_BYTE;
               EXEReadEnable <= '1';

            when 16#25# => -- LHU
               EXELoadType <= LOADTYPE_WORD;
               if (calcMemAddr(0) = '1') then
                  exceptionNew3    <= '1';
                  exceptionCode_3  <= x"4";
                  EXEReadException <= '1';
               else
                  EXEReadEnable <= '1';
               end if; 
               
            when 16#26# => -- LWR
               EXELoadType   <= LOADTYPE_RIGHT;
               EXEReadEnable <= '1';
               EXEresultData <= value2;    

            when 16#28# => -- SB
               case (to_integer(calcMemAddr(1 downto 0))) is 
                  when 0 => EXEMemWriteMask <= "0001"; EXEMemWriteData <= x"000000" & value2(7 downto 0); 
                  when 1 => EXEMemWriteMask <= "0010"; EXEMemWriteData <= x"0000" & value2(7 downto 0) & x"00";   
                  when 2 => EXEMemWriteMask <= "0100"; EXEMemWriteData <= x"00" & value2(7 downto 0) & x"0000";   
                  when 3 => EXEMemWriteMask <= "1000"; EXEMemWriteData <= value2(7 downto 0) & x"000000";   
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';

            when 16#29# => -- SH
               if (calcMemAddr(1) = '1') then
                  EXEMemWriteData <= value2(15 downto 0) & x"0000";
                  EXEMemWriteMask <= "1100";
               else
                  EXEMemWriteData <= x"0000" & value2(15 downto 0);
                  EXEMemWriteMask <= "0011";
               end if;
               if (calcMemAddr(0) = '1') then
                  exceptionNew3        <= '1';
                  exceptionCode_3      <= x"5";
                  EXEMemWriteException <= '1';
               else
                  EXEMemWriteEnable <= '1';
               end if;
               
            when 16#2A# => -- SWL
               case (to_integer(calcMemAddr(1 downto 0))) is 
                  when 0 => EXEMemWriteMask <= "0001"; EXEMemWriteData <= x"000000" & value2(31 downto 24);
                  when 1 => EXEMemWriteMask <= "0011"; EXEMemWriteData <= x"0000" & value2(31 downto 16);
                  when 2 => EXEMemWriteMask <= "0111"; EXEMemWriteData <= x"00" & value2(31 downto 8);
                  when 3 => EXEMemWriteMask <= "1111"; EXEMemWriteData <= value2;
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';   

            when 16#2B# => -- SW
               if (calcMemAddr(1 downto 0) /= "00") then
                  exceptionNew3        <= '1';
                  exceptionCode_3      <= x"5";
                  EXEMemWriteException <= '1';
               else
                  EXEMemWriteEnable <= '1';
               end if;
               
            when 16#2E# => -- SWR
               case (to_integer(calcMemAddr(1 downto 0))) is 
                  when 0 => EXEMemWriteMask <= "1111"; EXEMemWriteData <= value2;
                  when 1 => EXEMemWriteMask <= "1110"; EXEMemWriteData <= value2(23 downto 0) & x"00";
                  when 2 => EXEMemWriteMask <= "1100"; EXEMemWriteData <= value2(15 downto 0) & x"0000";
                  when 3 => EXEMemWriteMask <= "1000"; EXEMemWriteData <= value2( 7 downto 0) & x"000000";
                  when others => null;
               end case;
               EXEMemWriteEnable <= '1';    
            
            when 16#30# => -- LWC0 -> NOP 
               null;            

            when 16#31# => -- LWC1 -> NOP 
               null;    

            when 16#32# => -- LWC2
               if (cop0_SR(30) = '0') then -- COP2 disabled
                  exceptionNew3   <= '1';
                  exceptionCode_3 <= x"B";
               else
                  EXEGTeReadEnable <= '1';
                  EXELoadType      <= LOADTYPE_DWORD;
                  EXEReadEnable    <= '1';
               end if;                        
               
            when 16#33# => -- LWC3 -> NOP 
               null;    
               
            when 16#38# => -- SWC0 -> NOP 
               null;    
               
            when 16#39# => -- SWC1 -> NOP 
               null; 
               
            when 16#3A# => -- SWC2
               if (cop0_SR(30) = '0') then -- COP2 disabled
                  exceptionNew3   <= '1';
                  exceptionCode_3 <= x"B";
               else
                  EXEMemWriteEnable <= '1';
                  gte_readEna       <= '1';
                  EXEMemWriteData   <= gte_readData;
                  if (gte_busy = '1') then
                     stallNew3    <= '1';
                     EXEstalltype <= EXESTALLTYPE_GTE;
                  end if;
               end if; 
               
            when 16#3B# => -- SWC3 -> NOP 
               null; 
               
            when others => 
               exceptionNew3   <= '1';
               exceptionCode_3 <= x"A";
         
         end case;
             
      end if;
      
   end process;
   
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
         if (reset = '1') then
         
            stall3                        <= '0';
                       
            pcOld2                        <= (others => '0');
            opcode2                       <= (others => '0');
                        
            blockLoadforward              <= '0';
                  
            executeException              <= '0';
            resultWriteEnable             <= '0';
            resultData                    <= (others => '0');
            resultTarget                  <= (others => '0');
            executeBranchdelaySlot        <= '0';
            executeBranchTaken            <= '0';
            executeMemWriteData           <= (others => '0');
            executeMemWriteMask           <= (others => '0');
            executeMemWriteAddr           <= (others => '0');
            executeMemWriteEnable         <= '0';
            executeLoadType               <= LOADTYPE_DWORD;
            executeReadAddress            <= (others => '0');
            executeReadEnable             <= '0';
            executeCOP0WriteEnable        <= '0';
            executeCOP0WriteDestination   <= (others => '0');
            executeCOP0WriteValue         <= (others => '0');
            hiloWait                      <= 0;
            
         elsif (ce = '1') then
         
            DIVstart    <= '0';
               
            if (stall = 0) then
            
               if (exception(4 downto 2) > 0) then
               
                  executeException              <= '1';
                                                
                  stall3                        <= '0';
                     
                  resultWriteEnable             <= '0';
                  executeReadEnable             <= '0';
                  executeMemWriteEnable         <= '0';
                  executeGTEReadEnable          <= '0';
                  executeCOP0WriteEnable        <= '0';
                  
                  executeStalltype              <= EXESTALLTYPE_NONE;
                        
               else     
                     
                  executeException              <= decodeException;
                  pcOld2                        <= pcOld1;
                  opcode2                       <= opcode1;
                        
                  stall3                        <= stallNew3;
                        
                  -- from calculation     
                  resultWriteEnable             <= EXEresultWriteEnable;
                        
                  resultData                    <= EXEresultData;    
                  resultTarget                  <= EXEresultTarget;
                        
                  executeBranchdelaySlot        <= EXEBranchdelaySlot;
                  executeBranchTaken            <= EXEBranchTaken;       
      
                  executeMemWriteData           <= EXEMemWriteData;             
                  executeMemWriteMask           <= EXEMemWriteMask;             
                  executeMemWriteAddr           <= EXEMemAddr(31 downto 2) & "00";             
                  executeMemWriteEnable         <= EXEMemWriteEnable;  

                  executeLoadType               <= EXELoadType;   
                  executeReadAddress            <= EXEMemAddr;
                  executeReadEnable             <= EXEReadEnable; 
                  
                  executeGTEReadEnable          <= EXEGTeReadEnable;
                  executeGTETarget              <= decodeSource2;

                  executeCOP0WriteEnable        <= EXECOP0WriteEnable;     
                  executeCOP0WriteDestination   <= EXECOP0WriteDestination;
                  executeCOP0WriteValue         <= EXECOP0WriteValue; 

                  executeStalltype              <= EXEstalltype; 

                  execute_gte_writeAddr         <= EXEgte_writeAddr;
                  execute_gte_writeData         <= EXEgte_writeData;
                  execute_gte_writeEna          <= EXEgte_writeEna;

                  execute_gte_cmdData           <= EXEgte_cmdData;
                  execute_gte_cmdEna            <= EXEgte_cmdEna;                   

                  blockLoadforward <= '0';
                  if (executeReadEnable = '1' and EXEReadEnable = '1' and resultTarget = EXEresultTarget) then
                     blockLoadforward <= '1';
                  end if;                 
                  
                  -- new mul/div
                  if (EXEcalcMULT = '1') then
                     hilocalc <= HILOCALC_MULT;
                     mul1     <= value1;
                     mul2     <= value2;
                     if    (value1(31 downto 11) = 0 or value1(31 downto 11) = 16#1FFFFF#) then hiloWait <= 5;
                     elsif (value1(31 downto 20) = 0 or value1(31 downto 20) = 16#FFF#)    then hiloWait <= 8;
                     else  hiloWait <= 12;
                     end if;
                  end if;
                  
                  if (EXEcalcMULTU = '1') then
                     hilocalc <= HILOCALC_MULTU;
                     mul1     <= value1;
                     mul2     <= value2;
                     if    (value1(31 downto 11) = 0) then hiloWait <= 5;
                     elsif (value1(31 downto 20) = 0) then hiloWait <= 8;
                     else  hiloWait <= 12;
                     end if;
                  end if;
                  
                  if (EXEcalcDIV = '1') then
                     hiloWait    <= 38;
                     if (value2 = 0) then
                        hilocalc      <= HILOCALC_DIV0;
                        DIV0remainder <= value1;
                        if (signed(value1) >= 0) then
                           DIV0quotient <= (others => '1');
                        else
                           DIV0quotient <= x"00000001";
                        end if;
                     elsif (value1 = x"80000000" and value2 = x"FFFFFFFF") then
                        hilocalc      <= HILOCALC_DIV0;
                        DIV0quotient  <= x"80000000";
                        DIV0remainder <= (others => '0');
                     else
                        hilocalc    <= HILOCALC_DIV;
                        DIVstart    <= '1';
                        DIVdividend <= resize(signed(value1), 33);
                        DIVdivisor  <= resize(signed(value2), 33);
                     end if;
                  end if;
                  
                  if (EXEcalcDIVU = '1') then
                     hiloWait    <= 38;
                     if (value2 = 0) then
                        hilocalc      <= HILOCALC_DIV0;
                        DIV0remainder <= value1;
                        DIV0quotient  <= (others => '1');
                     else
                        hilocalc    <= HILOCALC_DIVU;
                        DIVstart    <= '1';
                        DIVdividend <= '0' & signed(value1);
                        DIVdivisor  <= '0' & signed(value2);
                     end if;
                  end if;
                  
                  if (EXEhiUpdate = '1') then hi <= value1; end if;
                  if (EXEloUpdate = '1') then lo <= value1; end if;
                  
               end if;
               
            end if;
            
            -- mul/div calc/wait
            if (hiloWait > 0) then
               hiloWait <= hiloWait - 1;
               if (hiloWait = 1) then
                  stall3 <= '0';
                  case (executeStalltype) is
                     when EXESTALLTYPE_READHI => resultData <= hi;
                     when EXESTALLTYPE_READLO => resultData <= lo;
                     when others => null;
                  end case;
               end if;
            end if;
            
            mulResultS <= signed(mul1) * signed(mul2);
            mulResultU <= mul1 * mul2;
            
            if (hiloWait = 2) then
               case (hilocalc) is
                  when HILOCALC_MULT  => hi <=   unsigned(mulResultS(63 downto 32));  lo <=    unsigned(mulResultS(31 downto 0));
                  when HILOCALC_MULTU => hi <=            mulResultU(63 downto 32);   lo <=             mulResultU(31 downto 0);
                  when HILOCALC_DIV   => hi <=  unsigned(DIVremainder(31 downto  0)); lo <=   unsigned(DIVquotient(31 downto 0));
                  when HILOCALC_DIVU  => hi <=  unsigned(DIVremainder(31 downto  0)); lo <=   unsigned(DIVquotient(31 downto 0));
                  when HILOCALC_DIV0  => hi <=           DIV0remainder;               lo <=            DIV0quotient;
               end case;
            end if;
            
            -- GTE
            if (executeStalltype = EXESTALLTYPE_GTE and gte_busy = '0') then
               resultData          <= gte_readData;
               executeMemWriteData <= gte_readData;
               stall3              <= '0';
               executeStalltype    <= EXESTALLTYPE_NONE;
            end if;
   
         end if;
         
      end if;
   end process;
   
   
--##############################################################
--############################### stage 4
--##############################################################
   
   scratchpad_address_a <= std_logic_vector(executeMemWriteAddr(9 downto 2));
   scratchpad_data_a    <= std_logic_vector(executeMemWriteData);
   
   scratchpad_address_b <= std_logic_vector(executeReadAddress(9 downto 2));
   
   gscratchpad: for i in 0 to 3 generate
   begin
      icache: entity work.dpram
      generic map ( addr_width => 8, data_width => 8)
      port map
      (
         clock_a     => clk1x,
         clken_a     => ce,
         address_a   => scratchpad_address_a,
         data_a      => scratchpad_data_a((8*i) + 7 downto (8*i)),
         wren_a      => scratchpad_wren_a(i),
         
         clock_b     => clk2x,
         address_b   => scratchpad_address_b,
         data_b      => x"00",
         wren_b      => '0',
         q_b         => scratchpad_q_b((8*i) + 7 downto (8*i))
      );
   end generate; 
   
   scratchpad_dataread <= unsigned(scratchpad_q_b);
   
   process (stall, exception, executeMemWriteEnable, executeMemWriteAddr, executeMemWriteData, cop0_SR, CACHECONTROL, stall4, executeReadEnable, executeReadAddress, executeLoadType, executeMemWriteMask)
      variable skipmem : std_logic;
   begin
   
      mem4_request   <= '0';
      stallNew4      <= stall4;
      
      WBCACHECONTROL <= CACHECONTROL;
      
      mem4_address   <= executeMemWriteAddr;
      mem4_rnw       <= '1';
      mem4_dataWrite <= std_logic_vector(executeMemWriteData);
      mem4_reqsize   <= "10";
      
      WBinvalidateCacheEna  <= '0';
      WBinvalidateCacheLine <= executeMemWriteAddr(11 downto 4);
      
      scratchpad_wren_a    <= "0000";
      
      if (exception(4 downto 3) = 0 and stall = 0) then
      
         if (executeMemWriteEnable = '1') then
            skipmem := '0';
         
            case (to_integer(unsigned(executeMemWriteAddr(31 downto 29)))) is
            
               when 0 | 4 => -- cached
                  if (cop0_SR(16) = '1') then -- cache isolation
                     skipmem               := '1';
                     WBinvalidateCacheEna  <= '1';
                  end if;
                  
                  if (executeMemWriteAddr(28 downto 10) = 16#7E000#) then -- scratchpad
                     skipmem := '1';
                     scratchpad_wren_a <= executeMemWriteMask;
                  end if;
                  
               when 6 | 7 => -- KSEG2
                  skipmem := '1';
                  if (executeMemWriteAddr = x"FFFE0130") then
                     WBCACHECONTROL <= executeMemWriteData;
                  end if;
               
               when others => null;
               
            end case;
            
            if (skipmem = '0') then
               mem4_request   <= '1';
               mem4_address   <= executeMemWriteAddr;
               mem4_rnw       <= '0';
               mem4_dataWrite <= std_logic_vector(executeMemWriteData);
               stallNew4      <= '1';
            end if;
         
         end if;
         
         if (executeReadEnable = '1') then

            case (executeLoadType) is
               when LOADTYPE_SBYTE => mem4_reqsize <= "00";
               when LOADTYPE_SWORD => mem4_reqsize <= "01";
               when LOADTYPE_LEFT  => mem4_reqsize <= "10"; 
               when LOADTYPE_DWORD => mem4_reqsize <= "10";
               when LOADTYPE_BYTE  => mem4_reqsize <= "00"; 
               when LOADTYPE_WORD  => mem4_reqsize <= "01"; 
               when LOADTYPE_RIGHT => mem4_reqsize <= "10";
            end case;

            if ((executeReadAddress(31 downto 29) = 0 or executeReadAddress(31 downto 29) = 4) and executeReadAddress(28 downto 10) = 16#7E000#) then
               --report "scratchpad access" severity failure;
            else 
               mem4_request   <= '1';
               mem4_address   <= executeReadAddress;
               if (executeLoadType = LOADTYPE_LEFT or executeLoadType = LOADTYPE_RIGHT) then 
                  mem4_address(1 downto 0) <= "00";
               end if;
               mem4_rnw       <= '1';
               stallNew4      <= '1';
            end if;
         
         end if;
         
      end if;
      
   end process;
   
   process (clk1x)
      variable dataReadEna  : std_logic;
      variable dataReadData : unsigned(31 downto 0);
      variable dataReadType : CPU_LOADTYPE;
      variable oldData      : unsigned(31 downto 0);
   begin
      if (rising_edge(clk1x)) then
         if (reset = '1') then
         
            stall4                           <= '0';
                              
            pcOld3                           <= (others => '0');
            opcode3                          <= (others => '0');
                              
            cop0_SR                          <= (others => '0');
            cop0_BPC                         <= (others => '0');
            cop0_BDA                         <= (others => '0');
            cop0_JUMPDEST                    <= (others => '0');
            cop0_DCIC                        <= (others => '0');
            cop0_BDAM                        <= (others => '0');
            cop0_BPCM                        <= (others => '0');
            cop0_CAUSE                       <= (others => '0');
            cop0_EPC                         <= (others => '0');
            cop0_PRID                        <= x"00000002";
                              
            CACHECONTROL                     <= (others => '0');
                        
            writebackTarget                  <= (others => '0');
            writebackData                    <= (others => '0');
            writebackWriteEnable             <= '0';
         
            writebackInvalidateCacheEna      <= '0';
            
            writebackException               <= '0';
         
         elsif (ce = '1') then
         
            stall4         <= stallNew4;
            dataReadEna    := '0';
            dataReadData   := unsigned(mem_dataRead);
            dataReadType   := writebackLoadType;
            oldData        := writebackData;
            
            writebackInvalidateCacheEna  <= WBinvalidateCacheEna; 
            writebackInvalidateCacheLine <= WBinvalidateCacheLine;   
            
            gte_writeEna  <= '0';
            gte_cmdEna    <= '0';
            
            if (stall = 0) then
            
               if (exception(4 downto 3) > 0) then
               
                  writebackException            <= '1'; 
                  
               else
               
                  pcOld3                        <= pcOld2;
                  opcode3                       <= opcode2;
                  writebackTarget               <= resultTarget;
                  writebackData                 <= resultData;
                  
                  writebackException            <= executeException;
                           
                  CACHECONTROL                  <= WBCACHECONTROL;
                  
                  writebackMemOPisRead          <= executeReadEnable;
                  
                  writebackGTEReadEnable       <= executeGTEReadEnable;
                  WBgte_writeAddr              <= '0' & executeGTETarget;
                  
                  if (executeCOP0WriteEnable = '1') then
                     case (to_integer(executeCOP0WriteDestination)) is
                        when 16#3# => cop0_BPC   <= executeCOP0WriteValue;
                        when 16#5# => cop0_BDA   <= executeCOP0WriteValue;
                        when 16#7# => cop0_DCIC  <= executeCOP0WriteValue and x"FF80F03F";
                        when 16#9# => cop0_BDAM  <= executeCOP0WriteValue;
                        when 16#B# => cop0_BPCM  <= executeCOP0WriteValue;
                        when 16#C# => cop0_SR    <= executeCOP0WriteValue and x"F27FFF3F";
                        when 16#D# => cop0_CAUSE <= executeCOP0WriteValue and x"00000300";
                        when others => null;
                     end case;
                  end if;
                  
                  if (executeException = '1') then
                     cop0_SR        <= exception_SR;
                     cop0_CAUSE     <= exception_CAUSE;
                     cop0_EPC       <= exception_EPC;  
                     cop0_JUMPDEST  <= exception_JMP;  
                  end if;
                  
                  writebackWriteEnable <= '0';
                  if (executeReadEnable = '1') then
                     if ((executeReadAddress(31 downto 29) = 0 or executeReadAddress(31 downto 29) = 4) and executeReadAddress(28 downto 10) = 16#7E000#) then -- scratchpad read
                        writebackWriteEnable <= '1';
                        oldData := resultData;
                        if (writebackTarget = resultTarget and writebackWriteEnable = '1') then
                           oldData := writebackData;
                        end if;

                        case (executeLoadType) is
                           when LOADTYPE_SBYTE => 
                              case (executeReadAddress(1 downto 0)) is 
                                 when "00" => writebackData <= unsigned(resize(signed(scratchpad_dataread( 7 downto  0)), 32));
                                 when "01" => writebackData <= unsigned(resize(signed(scratchpad_dataread(15 downto  8)), 32));
                                 when "10" => writebackData <= unsigned(resize(signed(scratchpad_dataread(23 downto 16)), 32));
                                 when "11" => writebackData <= unsigned(resize(signed(scratchpad_dataread(31 downto 24)), 32));
                                 when others => null;
                              end case;  
                                 
                           when LOADTYPE_SWORD => 
                              if (executeReadAddress(1) = '0') then
                                 writebackData <= unsigned(resize(signed(scratchpad_dataread(15 downto 0)), 32));
                              else
                                 writebackData <= unsigned(resize(signed(scratchpad_dataread(31 downto 16)), 32));
                              end if;
                                 
                           when LOADTYPE_LEFT =>
                              case (to_integer(executeReadAddress(1 downto 0))) is
                                 when 0 => writebackData <= scratchpad_dataread( 7 downto 0) & oldData(23 downto 0);
                                 when 1 => writebackData <= scratchpad_dataread(15 downto 0) & oldData(15 downto 0);
                                 when 2 => writebackData <= scratchpad_dataread(23 downto 0) & oldData( 7 downto 0); 
                                 when 3 => writebackData <= scratchpad_dataread;
                                 when others => null;
                              end case;
                                 
                           when LOADTYPE_DWORD => writebackData <= scratchpad_dataread;
                           
                           when LOADTYPE_BYTE  =>
                              case (executeReadAddress(1 downto 0)) is 
                                 when "00" => writebackData <= x"000000" & scratchpad_dataread( 7 downto  0);
                                 when "01" => writebackData <= x"000000" & scratchpad_dataread(15 downto  8);
                                 when "10" => writebackData <= x"000000" & scratchpad_dataread(23 downto 16);
                                 when "11" => writebackData <= x"000000" & scratchpad_dataread(31 downto 24);
                                 when others => null;
                              end case;  
                           
                           when LOADTYPE_WORD  => 
                              if (executeReadAddress(1) = '0') then
                                 writebackData <= x"0000" & scratchpad_dataread(15 downto 0);
                              else
                                 writebackData <= x"0000" & scratchpad_dataread(31 downto 16);
                              end if;
                           
                           when LOADTYPE_RIGHT =>
                              case (to_integer(executeReadAddress(1 downto 0))) is
                                 when 0 => writebackData <= scratchpad_dataread;
                                 when 1 => writebackData <= oldData(31 downto 24) & scratchpad_dataread(31 downto  8);
                                 when 2 => writebackData <= oldData(31 downto 16) & scratchpad_dataread(31 downto 16);
                                 when 3 => writebackData <= oldData(31 downto  8) & scratchpad_dataread(31 downto 24);
                                 when others => null;
                              end case;
                        end case;
                     
                     else
                        writebackLoadType    <= executeLoadType;
                        writebackReadAddress <= executeReadAddress;
                     end if;
                  else
                     writebackWriteEnable <= resultWriteEnable;
                  end if;
                  
                  if (execute_gte_writeEna = '1') then
                     gte_writeAddr <= execute_gte_writeAddr;
                     gte_writeData <= execute_gte_writeData;
                     gte_writeEna  <= '1';
                  end if;
                  
                  if (execute_gte_cmdEna = '1') then
                     gte_cmdData <= execute_gte_cmdData;
                     gte_cmdEna  <= '1';
                  end if;
                  
                  
               end if;
               
            else

               if (mem_done = '1' and memoryMuxStage = 4) then
                  stall4 <= '0';
                  if (writebackMemOPisRead = '1') then
                     dataReadEna := '1';
                  end if;
               end if;
               
            end if;
            
            if (dataReadEna = '1') then
               if (writebackGTEReadEnable = '1') then
                  gte_writeAddr <= WBgte_writeAddr;
                  gte_writeData <= dataReadData;
                  gte_writeEna  <= '1';
               else
                  writebackWriteEnable <= '1';
                  if (writeDoneTarget = writebackTarget and writeDoneWriteEnable = '1') then
                     oldData := writeDoneData;
                  end if;
                  case (dataReadType) is
                     
                     when LOADTYPE_SBYTE => writebackData <= unsigned(resize(signed(dataReadData(7 downto 0)), 32));
                     when LOADTYPE_SWORD => writebackData <= unsigned(resize(signed(dataReadData(15 downto 0)), 32));
                     when LOADTYPE_LEFT =>
                        case (to_integer(writebackReadAddress(1 downto 0))) is
                           when 0 => writebackData <= dataReadData( 7 downto 0) & oldData(23 downto 0);
                           when 1 => writebackData <= dataReadData(15 downto 0) & oldData(15 downto 0);
                           when 2 => writebackData <= dataReadData(23 downto 0) & oldData( 7 downto 0); 
                           when 3 => writebackData <= dataReadData;
                           when others => null;
                        end case;
                           
                     when LOADTYPE_DWORD => writebackData <= dataReadData;
                     when LOADTYPE_BYTE  => writebackData <= x"000000" & dataReadData(7 downto 0);
                     when LOADTYPE_WORD  => writebackData <= x"0000" & dataReadData(15 downto 0);
                     when LOADTYPE_RIGHT =>
                        case (to_integer(writebackReadAddress(1 downto 0))) is
                           when 0 => writebackData <= dataReadData;
                           when 1 => writebackData <= oldData(31 downto 24) & dataReadData(31 downto  8);
                           when 2 => writebackData <= oldData(31 downto 16) & dataReadData(31 downto 16);
                           when 3 => writebackData <= oldData(31 downto  8) & dataReadData(31 downto 24);
                           when others => null;
                        end case;
                        
                  end case;
               end if;   
            end if;
   
            cop0_CAUSE(10) <= irqRequest;
   
         end if;
      end if;
   end process;
   
   
   
--##############################################################
--############################### stage 5
--##############################################################
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         cpu_done <= '0';
      
         if (reset = '1') then
         
            stall5               <= '0';
            
            pcOld4               <= (others => '0');
            opcode4              <= (others => '0');
            
            for i in 0 to 31 loop
               regs(i) <= (others => '0');
            end loop;
            
            writeDoneTarget      <= (others => '0');
            writeDoneData        <= (others => '0');
            writeDoneWriteEnable <= '0';
            
            debugCnt             <= (others => '0');
         
         elsif (ce = '1') then
            
            if (stall = 0) then
            
               pcOld4               <= pcOld3;
               opcode4              <= opcode3;
               
               writeDoneTarget      <= writebackTarget;     
               writeDoneData        <= writebackData;       
               writeDoneWriteEnable <= writebackWriteEnable;
               
               if (writebackWriteEnable = '1' and writebackException = '0') then 
                  if (writebackTarget > 0) then
                     regs(to_integer(writebackTarget)) <= writebackData;
                  end if;
               end if;
               
               -- export
               debugCnt          <= debugCnt+ 1;
               cpu_done          <= '1';
               cpu_export.pc     <= pcOld4;
               cpu_export.opcode <= opcode4;
               cpu_export.cause  <= cop0_CAUSE;
               for i in 0 to 31 loop
                  cpu_export.regs(i) <= regs(i);
               end loop;
               
               -- todo: REMOVE!
               --if (debugCnt(31) = '1' and writebackTarget = 0) then
               --   cop0_CAUSE(9) <= '0';
               --end if;
               
            end if;
   
         end if;
      end if;
   end process;
   
--##############################################################
--############################### exception handling
--##############################################################
   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (reset = '1') then
         
            exception            <= (others => '0');
         
            cop0_BADVADDR        <= (others => '0');

         elsif (ce = '1') then
            
            if (stall = 0) then
         
               exception <= exceptionNew;
               if (exceptionNew1 = '1') then    -- PC out of bounds
                  exceptionCode     <= x"6";
                  exceptionInstr    <= opcode2(27 downto 26);
                  exception_PC      <= PCnext;
                  exception_branch  <= executeBranchTaken;
                  exception_brslot  <= executeBranchdelaySlot;
               elsif (exceptionNew5 = '1') then -- interrupt
                  exceptionCode     <= x"0";
                  exceptionInstr    <= opcode1(27 downto 26);
                  exception_PC      <= pcOld1;
                  exception_branch  <= executeBranchTaken;
                  exception_brslot  <= executeBranchdelaySlot;
               else                             -- execute stage
                  exceptionCode     <= exceptionCode_3;
                  exceptionInstr    <= opcode1(27 downto 26);
                  if (EXEBranchTaken = '1') then
                     exception_PC      <= PCbranch;
                     exception_branch  <= '0';
                     exception_brslot  <= '0';
                     if (exceptionNew3 = '1') then
                        cop0_BADVADDR     <= PCbranch;
                     end if;
                  else
                     exception_PC      <= PCold1;
                     exception_branch  <= executeBranchTaken;
                     exception_brslot  <= executeBranchdelaySlot;
                     if (EXEMemWriteException = '1' or EXEReadException = '1') then
                        cop0_BADVADDR  <= EXEMemAddr;
                     end if;
                  end if;
               end if;
               exception_JMPnext <= PCold0;
               
               if (exception > 0) then
                  exception_SR    <= cop0_SR(31 downto 6) & cop0_SR(3 downto 0) & "00";
                  exception_CAUSE <= cop0_CAUSE;
                  exception_CAUSE(5 downto 2)   <= exceptionCode;
                  exception_CAUSE(29 downto 28) <= exceptionInstr; 
                  exception_CAUSE(30) <= exception_branch;
                  exception_CAUSE(31) <= exception_brslot;
                  if (exception_brslot = '1') then
                     exception_EPC <= exception_PC - 4;
                     exception_JMP <= exception_JMPnext;
                  else
                     exception_EPC <= exception_PC;
                  end if;
               end if;
               
            end if;
   
         end if;
      end if;
   end process;
   
   idivider : entity work.divider
   port map
   (
      clk       => clk1x,      
      start     => DIVstart,
      done      => open,      
      busy      => open,
      dividend  => DIVdividend, 
      divisor   => DIVdivisor,  
      quotient  => DIVquotient, 
      remainder => DIVremainder
   );
   

end architecture;





