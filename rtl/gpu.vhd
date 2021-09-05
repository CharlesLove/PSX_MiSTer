library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pGPU.all;

entity gpu is
   port 
   (
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;
      clk2xIndex           : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      isPal                : in  std_logic;
      
      bus_addr             : in  unsigned(3 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0);
                     
      vram_BUSY            : in  std_logic;                    
      vram_DOUT            : in  std_logic_vector(63 downto 0);
      vram_DOUT_READY      : in  std_logic;
      vram_BURSTCNT        : out std_logic_vector(7 downto 0) := (others => '0'); 
      vram_ADDR            : out std_logic_vector(19 downto 0) := (others => '0');                       
      vram_DIN             : out std_logic_vector(63 downto 0) := (others => '0');
      vram_BE              : out std_logic_vector(7 downto 0) := (others => '0'); 
      vram_WE              : out std_logic := '0';
      vram_RD              : out std_logic := '0';     

      hsync                : out std_logic := '0';
      vsync                : out std_logic := '0';
      hblank               : out std_logic := '0';
      vblank               : out std_logic := '0';
      
      export_gtm           : out unsigned(11 downto 0);
      export_line          : out unsigned(11 downto 0);
      export_gpus          : out unsigned(31 downto 0)
   );
end entity;

architecture arch of gpu is
  
   signal softReset                 : std_logic := '0';
   
   signal GPUREAD                   : std_logic_vector(31 downto 0) := (others => '0');
   signal GPUSTAT                   : std_logic_vector(31 downto 0) := (others => '0');
   signal GPUSTAT_TextPageX         : std_logic_vector(3 downto 0);
   signal GPUSTAT_TextPageY         : std_logic;
   signal GPUSTAT_Transparency      : std_logic_vector(1 downto 0);
   signal GPUSTAT_TextPageColors    : std_logic_vector(1 downto 0);
   signal GPUSTAT_Dither            : std_logic;
   signal GPUSTAT_DrawToDisplay     : std_logic;
   signal GPUSTAT_SetMask           : std_logic;
   signal GPUSTAT_DrawPixelsMask    : std_logic;
   signal GPUSTAT_InterlaceField    : std_logic;
   signal GPUSTAT_ReverseFlag       : std_logic;
   signal GPUSTAT_TextureDisable    : std_logic;
   signal GPUSTAT_HorRes2           : std_logic;
   signal GPUSTAT_HorRes1           : std_logic_vector(1 downto 0);
   signal GPUSTAT_VerRes            : std_logic;
   signal GPUSTAT_PalVideoMode      : std_logic;
   signal GPUSTAT_ColorDepth24      : std_logic;
   signal GPUSTAT_VertInterlace     : std_logic;
   signal GPUSTAT_DisplayDisable    : std_logic;
   signal GPUSTAT_IRQRequest        : std_logic;
   signal GPUSTAT_DMADataRequest    : std_logic;
   signal GPUSTAT_ReadyRecCmd       : std_logic;
   signal GPUSTAT_ReadySendVRAM     : std_logic;
   signal GPUSTAT_ReadyRecDMA       : std_logic;
   signal GPUSTAT_DMADirection      : std_logic_vector(1 downto 0);
   signal GPUSTAT_DrawingOddline    : std_logic;
      
   signal vramRange                 : unsigned(18 downto 0) := (others => '0');
   alias vramRangeY                 : unsigned is vramRange(18 downto 10);
   signal hDisplayRange             : unsigned(23 downto 0) := (others => '0');
   signal vDisplayRange             : unsigned(19 downto 0) := (others => '0');
      
   signal drawMode                  : unsigned(13 downto 0) := (others => '0');
      
   signal textureWindow             : unsigned(19 downto 0) := (others => '0');
   signal textureWindow_AND_X       : unsigned(7 downto 0) := (others => '0');
   signal textureWindow_AND_Y       : unsigned(7 downto 0) := (others => '0');
      
   signal drawingAreaLeft           : unsigned(9 downto 0) := (others => '0');
   signal drawingAreaRight          : unsigned(9 downto 0) := (others => '0');
   signal drawingAreaTop            : unsigned(8 downto 0) := (others => '0');
   signal drawingAreaBottom         : unsigned(8 downto 0) := (others => '0');
   signal drawingOffsetX            : signed(10 downto 0) := (others => '0');
   signal drawingOffsetY            : signed(10 downto 0) := (others => '0');
      
   signal nextHCount                : integer range 0 to 4095;
   signal vpos                      : integer range 0 to 511;
   signal inVsync                   : std_logic := '0';
   signal interlacedDisplayField    : std_logic := '0';
   signal activeLineLSB             : std_logic := '0';
   signal interlacedDrawing         : std_logic;
      
   signal htotal                    : integer range 2169 to 2173; -- 3406 to 3413 in GPU clock domain
   signal vtotal                    : integer range 263 to 314;
   signal vDisplayStart             : integer range 0 to 314;
   signal vDisplayEnd               : integer range 0 to 314;
      
   -- FIFO IN  
   signal fifoIn_reset              : std_logic; 
   signal fifoIn_Din                : std_logic_vector(31 downto 0);
   signal fifoIn_Wr                 : std_logic; 
   signal fifoIn_Full               : std_logic;
   signal fifoIn_NearFull           : std_logic;
   signal fifoIn_Dout               : std_logic_vector(31 downto 0);
   signal fifoIn_Rd                 : std_logic;
   signal fifoIn_Empty              : std_logic;
   signal fifoIn_Valid              : std_logic;
      
   -- Processing  
   signal proc_idle                 : std_logic;
   signal proc_done                 : std_logic;
   signal proc_requestFifo          : std_logic;
   signal pixelStall                : std_logic;
   signal pixelColor                : std_logic_vector(15 downto 0);
   signal pixelAddr                 : unsigned(19 downto 0);
   signal pixelWrite                : std_logic;
      
   signal pixel64data               : std_logic_vector(63 downto 0) := (others => '0');
   signal pixel64wordEna            : std_logic_vector(3 downto 0) := (others => '0');
   signal pixel64addr               : std_logic_vector(16 downto 0) := (others => '0');
   signal pixel64filled             : std_logic := '0';
   signal pixel64timeout            : integer range 0 to 15;
      
   -- workers  
   signal vramFill_requestFifo      : std_logic; 
   signal vramFill_done             : std_logic; 
   signal vramFill_pixelColor       : std_logic_vector(15 downto 0);
   signal vramFill_pixelAddr        : unsigned(19 downto 0);
   signal vramFill_pixelWrite       : std_logic;   
      
   signal cpu2vram_requestFifo      : std_logic; 
   signal cpu2vram_done             : std_logic; 
   signal cpu2vram_pixelColor       : std_logic_vector(15 downto 0);
   signal cpu2vram_pixelAddr        : unsigned(19 downto 0);
   signal cpu2vram_pixelWrite       : std_logic;
      
   signal vram2vram_requestFifo     : std_logic; 
   signal vram2vram_done            : std_logic; 
   signal vram2vram_pixelColor      : std_logic_vector(15 downto 0);
   signal vram2vram_pixelAddr       : unsigned(19 downto 0);
   signal vram2vram_pixelWrite      : std_logic;
   signal vram2vram_reqVRAMEnable   : std_logic;
   signal vram2vram_reqVRAMXPos     : unsigned(9 downto 0);
   signal vram2vram_reqVRAMYPos     : unsigned(8 downto 0);
   signal vram2vram_reqVRAMSize     : unsigned(10 downto 0);
   signal vram2vram_vramLineEna     : std_logic;
   signal vram2vram_vramLineAddr    : unsigned(9 downto 0);
   
   signal line_requestFifo          : std_logic; 
   signal line_done                 : std_logic;
   type t_linediv_array is array(0 to 5) of div_type;
   signal line_div                  : t_linediv_array;
   signal line_pipeline_new         : std_logic;
   signal line_pipeline_transparent : std_logic;
   signal line_pipeline_x           : unsigned(9 downto 0);
   signal line_pipeline_y           : unsigned(8 downto 0);
   signal line_pipeline_cr          : unsigned(7 downto 0);
   signal line_pipeline_cg          : unsigned(7 downto 0);
   signal line_pipeline_cb          : unsigned(7 downto 0);
   signal line_reqVRAMEnable        : std_logic;
   signal line_reqVRAMXPos          : unsigned(9 downto 0);
   signal line_reqVRAMYPos          : unsigned(8 downto 0);
   signal line_reqVRAMSize          : unsigned(10 downto 0);
   signal line_vramLineEna          : std_logic;
   signal line_vramLineAddr         : unsigned(9 downto 0);
   
   signal rect_requestFifo          : std_logic; 
   signal rect_done                 : std_logic;
   signal rect_pipeline_new         : std_logic;
   signal rect_pipeline_texture     : std_logic;
   signal rect_pipeline_transparent : std_logic;
   signal rect_pipeline_rawTexture  : std_logic;
   signal rect_pipeline_x           : unsigned(9 downto 0);
   signal rect_pipeline_y           : unsigned(8 downto 0);
   signal rect_pipeline_cr          : unsigned(7 downto 0);
   signal rect_pipeline_cg          : unsigned(7 downto 0);
   signal rect_pipeline_cb          : unsigned(7 downto 0);
   signal rect_pipeline_u           : unsigned(7 downto 0);
   signal rect_pipeline_v           : unsigned(7 downto 0);
   signal rect_reqVRAMEnable        : std_logic;
   signal rect_reqVRAMXPos          : unsigned(9 downto 0);
   signal rect_reqVRAMYPos          : unsigned(8 downto 0);
   signal rect_reqVRAMSize          : unsigned(10 downto 0);
   signal rect_vramLineEna          : std_logic;
   signal rect_vramLineAddr         : unsigned(9 downto 0);
   
   signal pipeline_pixelColor       : std_logic_vector(15 downto 0);
   signal pipeline_pixelAddr        : unsigned(19 downto 0);
   signal pipeline_pixelWrite       : std_logic;
   signal pipeline_reqVRAMEnable    : std_logic;
   signal pipeline_reqVRAMXPos      : unsigned(9 downto 0);
   signal pipeline_reqVRAMYPos      : unsigned(8 downto 0);
   signal pipeline_reqVRAMSize      : unsigned(10 downto 0);
   
   signal pipeline_stall            : std_logic;
   signal pipeline_new              : std_logic;
   signal pipeline_texture          : std_logic;
   signal pipeline_transparent      : std_logic;
   signal pipeline_rawTexture       : std_logic;
   signal pipeline_x                : unsigned(9 downto 0);
   signal pipeline_y                : unsigned(8 downto 0);
   signal pipeline_cr               : unsigned(7 downto 0);
   signal pipeline_cg               : unsigned(7 downto 0);
   signal pipeline_cb               : unsigned(7 downto 0);
   signal pipeline_u                : unsigned(7 downto 0);
   signal pipeline_v                : unsigned(7 downto 0);
      
   -- FIFO OUT 
   signal fifoOut_reset             : std_logic; 
   signal fifoOut_Din               : std_logic_vector(84 downto 0);
   signal fifoOut_Wr                : std_logic; 
   signal fifoOut_Full              : std_logic;
   signal fifoOut_NearFull          : std_logic;
   signal fifoOut_Dout              : std_logic_vector(84 downto 0);
   signal fifoOut_Rd                : std_logic;
   signal fifoOut_Empty             : std_logic;
   signal fifoOut_Valid             : std_logic;
   
   -- vram access
   type tvramState is
   (
      IDLE,
      WRITEPIXEL,
      READVRAM
   );
   signal vramState : tvramState := IDLE;
   
   signal reqVRAMIdle               : std_logic;
   signal reqVRAMDone               : std_logic;
   
   signal reqVRAMEnable             : std_logic;
   signal reqVRAMXPos               : unsigned(9 downto 0);
   signal reqVRAMYPos               : unsigned(8 downto 0);
   signal reqVRAMSize               : unsigned(10 downto 0);
   signal reqVRAMremain             : unsigned(7 downto 0);
   signal reqVRAMnext               : unsigned(6 downto 0);
   signal reqVRAMaddr               : unsigned(7 downto 0) := (others => '0');
   
   signal vramLineAddr              : unsigned(9 downto 0);
   
   signal vramLineData              : std_logic_vector(15 downto 0);
   
   
begin 

   export_gtm  <= to_unsigned(nextHCount, 12);
   export_line <= to_unsigned(vpos, 12);
   export_gpus <= unsigned(GPUSTAT);


   GPUSTAT(3 downto 0)     <= GPUSTAT_TextPageX;
   GPUSTAT(4)              <= GPUSTAT_TextPageY;
   GPUSTAT(6 downto 5)     <= GPUSTAT_Transparency;
   GPUSTAT(8 downto 7)     <= GPUSTAT_TextPageColors;
   GPUSTAT(9)              <= GPUSTAT_Dither;
   GPUSTAT(10)             <= GPUSTAT_DrawToDisplay;
   GPUSTAT(11)             <= GPUSTAT_SetMask;
   GPUSTAT(12)             <= GPUSTAT_DrawPixelsMask;
   GPUSTAT(13)             <= GPUSTAT_InterlaceField;
   GPUSTAT(14)             <= GPUSTAT_ReverseFlag;
   GPUSTAT(15)             <= GPUSTAT_TextureDisable;
   GPUSTAT(16)             <= GPUSTAT_HorRes2;
   GPUSTAT(18 downto 17)   <= GPUSTAT_HorRes1;
   GPUSTAT(19)             <= GPUSTAT_VerRes;
   GPUSTAT(20)             <= GPUSTAT_PalVideoMode;
   GPUSTAT(21)             <= GPUSTAT_ColorDepth24;
   GPUSTAT(22)             <= GPUSTAT_VertInterlace;
   GPUSTAT(23)             <= GPUSTAT_DisplayDisable;
   GPUSTAT(24)             <= GPUSTAT_IRQRequest;
   GPUSTAT(25)             <= GPUSTAT_DMADataRequest;
   GPUSTAT(26)             <= GPUSTAT_ReadyRecCmd;
   GPUSTAT(27)             <= GPUSTAT_ReadySendVRAM;
   GPUSTAT(28)             <= GPUSTAT_ReadyRecDMA;
   GPUSTAT(30 downto 29)   <= GPUSTAT_DMADirection;
   GPUSTAT(31)             <= GPUSTAT_DrawingOddline;

   process (clk1x)
      variable mode480i                  : std_logic;
      variable isVsync                   : std_logic;
      variable vposNew                   : integer range 0 to 511;
      variable interlacedDisplayFieldNew : std_logic;
      
      variable cmdNew                    : unsigned(7 downto 0);
   begin
      if rising_edge(clk1x) then
      
         fifoIn_reset  <= '0';
         fifoOut_reset <= '0';
         
         if (nextHCount < 200) then hsync  <= '1'; else hsync  <= '0'; end if;
         if (nextHCount < 400) then hblank <= '1'; else hblank <= '0'; end if;
         
         vblank <= inVsync;
         if (vpos = vtotal - 4) then vsync <= '1'; end if; 
         if (vpos = vtotal - 2) then vsync <= '0'; end if; 
         
      
         if (reset = '1') then
               
            GPUSTAT_PalVideoMode    <= isPal;
            
            interlacedDisplayField  <= '0';
            
            softReset               <= '1';
            
            fifoIn_reset            <= '1';
            fifoOut_reset           <= '1';

         elsif (ce = '1') then
         
            bus_dataRead <= (others => '0');
            softReset    <= '0';

            -- bus read
            if (bus_read = '1') then
               if (bus_addr(3 downto 2) = "00") then
                  bus_dataRead <= GPUREAD;
               elsif (bus_addr(3 downto 2) = "01") then
                  bus_dataRead <= GPUSTAT;
               else
                  bus_dataRead <= x"FFFFFFFF";
               end if;
            end if;

            -- bus write
            if (bus_write = '1') then
            
               if (bus_addr = 4) then
                  
                  case (to_integer(unsigned(bus_dataWrite(29 downto 24)))) is
                     when 16#00# => -- reset
                        softReset <= '1';
                        
                     when 16#01# => -- clear fifo
                        report "GP1 clear fifo not implemented" severity failure;    
                        
                     when 16#02# => -- ack irq
                        GPUSTAT_IRQRequest <= '0';
                        
                     when 16#03# => -- display on/off
                        GPUSTAT_DisplayDisable <= bus_dataWrite(0);
                        
                     when 16#04# => -- DMA direction
                        GPUSTAT_DMADirection <= bus_dataWrite(1 downto 0);
                        
                     when 16#05# => -- Start of Display area (in VRAM)
                        vramRange <= unsigned(bus_dataWrite(18 downto 1)) & '0';
                        
                     when 16#06# => -- horizontal diplay range
                        hDisplayRange <= unsigned(bus_dataWrite(23 downto 0));
                        
                     when 16#07# => -- vertical diplay range
                        vDisplayRange <= unsigned(bus_dataWrite(19 downto 0));
                        
                     when 16#08# => -- Set display mode
                        GPUSTAT_HorRes1       <= bus_dataWrite(1 downto 0);
                        GPUSTAT_VertInterlace <= bus_dataWrite(2);
                        GPUSTAT_PalVideoMode  <= bus_dataWrite(3);
                        GPUSTAT_ColorDepth24  <= bus_dataWrite(4);
                        GPUSTAT_VertInterlace <= bus_dataWrite(5);
                        GPUSTAT_HorRes2       <= bus_dataWrite(6);
                        GPUSTAT_ReverseFlag   <= bus_dataWrite(7);
                        
                     when 16#09# => -- Set display mode
                        GPUSTAT_TextureDisable <= bus_dataWrite(0);
                          
                     when 16#10# | 16#11# | 16#12# | 16#13# | 16#14# | 16#15# | 16#16# | 16#17# | 16#18# | 16#19# | 16#1A# | 16#1B# | 16#1C# | 16#1D# | 16#1E# | 16#1F# => -- GPUInfo
                        case (to_integer(unsigned(bus_dataWrite(2 downto 0)))) is
                           when 2 => --Get Texture Window
                              GPUREAD <= x"000" & std_logic_vector(textureWindow);
                           
                           when 3 => --Get Draw Area Top Left
                              GPUREAD <= x"000" & '0' & std_logic_vector(drawingAreaTop) & std_logic_vector(drawingAreaLeft);
                           
                           when 4 => --Get Draw Area Bottom Right
                              GPUREAD <= x"000" & '0' & std_logic_vector(drawingAreaBottom) & std_logic_vector(drawingAreaRight);
                           
                           when 5 => --Get Drawing Offset
                              GPUREAD <= x"00" & "00" & std_logic_vector(drawingOffsetY) & std_logic_vector(drawingOffsetX);
                           
                           when others => null;
                        end case;
                     
                     when others => report "GP1 Command not implemented" severity failure; 
                  end case;
               
               end if;
            
            end if;
            
            --gpu timing calc
            if (GPUSTAT_PalVideoMode = '1') then
               htotal <= 2169;
               vtotal <= 314;
            else
               htotal <= 2173;
               vtotal <= 263;
            end if;
            
            if (vDisplayRange( 9 downto  0) < 314) then vDisplayStart <= to_integer(vDisplayRange( 9 downto  0)); else vDisplayStart <= 314; end if;
            if (vDisplayRange(19 downto 10) < 314) then vDisplayEnd   <= to_integer(vDisplayRange(19 downto 10)); else vDisplayEnd   <= 314; end if;
              
            -- gpu timing count
            if (nextHCount > 1) then
               nextHCount <= nextHCount - 1;
            else
               
               nextHCount <= htotal;
               
               vposNew := vpos + 1;
               if (vposNew >= vtotal) then
                  vposNew := 0;
                  if (GPUSTAT_VertInterlace = '1') then
                     GPUSTAT_InterlaceField <= not GPUSTAT_InterlaceField;
                  else
                     GPUSTAT_InterlaceField <= '0';
                  end if;
               end if;
               
               vpos <= vposNew;
               
               -- todo: timer 1
               
               mode480i := '0';
               if (GPUSTAT_VerRes = '1' and GPUSTAT_VertInterlace = '1') then mode480i := '1'; end if;
               
               isVsync := '0';
               if (vposNew < vDisplayStart or vposNew >= vDisplayEnd) then isVsync := '1'; end if;

               interlacedDisplayFieldNew := interlacedDisplayField;
               if (isVsync /= inVsync) then
                  if (isVsync = '1') then
                     --PSXRegs.setIRQ(0);
                     if (mode480i = '1') then 
                        interlacedDisplayFieldNew := not GPUSTAT_InterlaceField;
                     else 
                        interlacedDisplayFieldNew := '0';
                     end if;
                     --GPU.finishFrame();
                  end if;
                  inVsync <= isVsync;
                  --Timer.gateChange(1, inVsync);
               end if;
               interlacedDisplayField <= interlacedDisplayFieldNew;
               
             
               GPUSTAT_DrawingOddline <= '0';
               activeLineLSB          <= '0';
               if (mode480i = '1') then
                  if (vramRange(10) = '0' and interlacedDisplayFieldNew = '1') then activeLineLSB <= '1'; end if;
                  if (vramRange(10) = '1' and interlacedDisplayFieldNew = '0') then activeLineLSB <= '1'; end if;
               
                  if (vramRange(10) = '0' and isVsync = '0' and interlacedDisplayFieldNew = '1') then GPUSTAT_DrawingOddline <= '1'; end if;
                  if (vramRange(10) = '1' and isVsync = '1' and interlacedDisplayFieldNew = '0') then GPUSTAT_DrawingOddline <= '1'; end if;
               else
                  if (vramRange(10) = '0' and (vposNew mod 2) = 1) then GPUSTAT_DrawingOddline <= '1'; end if;
                  if (vramRange(10) = '1' and (vposNew mod 2) = 0) then GPUSTAT_DrawingOddline <= '1'; end if;
               end if;
               
            end if;
            
            -- softreset
            if (softReset = '1') then
               vramRange              <= (others => '0');
               hDisplayRange          <= x"C60260";
               vDisplayRange          <= x"3FC10";
                    
               nextHCount             <= htotal;
                 
               vpos                   <= 0;
               inVsync                <= '0';
                     
               GPUSTAT_DrawPixelsMask <= '0';
               GPUSTAT_InterlaceField <= '1';
               GPUSTAT_ReverseFlag    <= '0';
               GPUSTAT_TextureDisable <= '0';
               GPUSTAT_HorRes2        <= '0';
               GPUSTAT_HorRes1        <= "00";
               GPUSTAT_VerRes         <= '0';
               GPUSTAT_PalVideoMode   <= isPal;
               GPUSTAT_ColorDepth24   <= '0';
               GPUSTAT_VertInterlace  <= '0';
               GPUSTAT_DisplayDisable <= '1';
               GPUSTAT_IRQRequest     <= '0';
               GPUSTAT_DMADataRequest <= '0';
               GPUSTAT_DMADirection   <= "00";
               GPUSTAT_DrawingOddline <= '0';

            end if;

         end if;
      end if;
   end process;
   
   iSyncFifo_IN: entity mem.SyncFifo
   generic map
   (
      SIZE             => 32, -- 16 is correct, but only allows 15 entries -> muse nearfull or allow this big for broken homebrew?
      DATAWIDTH        => 32,
      NEARFULLDISTANCE => 16
   )
   port map
   ( 
      clk      => clk2x,
      reset    => fifoIn_reset,  
      Din      => fifoIn_Din,     
      Wr       => fifoIn_Wr,      
      Full     => fifoIn_Full,    
      NearFull => fifoIn_NearFull,
      Dout     => fifoIn_Dout,    
      Rd       => fifoIn_Rd,      
      Empty    => fifoIn_Empty   
   );
   
   fifoIn_Rd <= ce and (proc_idle or proc_requestFifo) and not fifoIn_Empty and not fifoIn_Valid;
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
      
         if (reset = '1') then
            
         elsif (ce = '1') then
         
            fifoIn_Wr  <= '0';
            fifoIn_Din <= bus_dataWrite;
         
            if (clk2xIndex = '1' and bus_write = '1' and bus_addr = 0) then
               fifoIn_Wr <= '1';
            end if;
            
         end if;

      end if;
   end process;
   
   process (clk2x)
      variable cmdNew : unsigned(7 downto 0);
   begin
      if rising_edge(clk2x) then
      
         fifoIn_Valid <= fifoIn_Rd;
      
         if (reset = '1') then
         
            proc_idle <= '1';
            
            textureWindow           <= (others => '0');
            textureWindow_AND_X     <= (others => '1');
            textureWindow_AND_Y     <= (others => '1');
               
            drawingAreaLeft         <= (others => '0');
            drawingAreaRight        <= (others => '0');
            drawingAreaTop          <= (others => '0');
            drawingAreaBottom       <= (others => '0');
            drawingOffsetX          <= (others => '0');
            drawingOffsetY          <= (others => '0');
            
         elsif (ce = '1') then
         
            if (fifoIn_Valid = '1') then
               
               cmdNew := unsigned(fifoIn_Dout(31 downto 24));
               
               if ((cmdNew >= 16#20# and cmdNew <=16#DF#) or cmdNew = 16#02#) then
                  
                  proc_idle           <= '0';
                  GPUSTAT_ReadyRecCmd <= '0';
                  
               elsif (cmdNew = 16#01#) then -- clear cache
                  -- todo
                  
               elsif (cmdNew = 16#1F#) then -- irq request
                  --GPUSTAT_IRQRequest <= '1'; todo
                  
               elsif (cmdNew = 16#E1#) then -- Draw Mode setting
                  GPUSTAT_TextPageX      <= fifoIn_Dout(3 downto 0);
                  GPUSTAT_TextPageY      <= fifoIn_Dout(4);
                  GPUSTAT_Transparency   <= fifoIn_Dout(6 downto 5);
                  GPUSTAT_TextPageColors <= fifoIn_Dout(8 downto 7);
                  GPUSTAT_Dither         <= fifoIn_Dout(9);
                  GPUSTAT_DrawToDisplay  <= fifoIn_Dout(10);
                  GPUSTAT_SetMask        <= fifoIn_Dout(11);
                  drawMode               <= unsigned(fifoIn_Dout(13 downto 0));
                  
               elsif (cmdNew = 16#E2#) then -- Set Texture window
                  -- todo
                  
               elsif (cmdNew = 16#E3#) then -- Set Drawing Area top left (X1,Y1)
                  drawingAreaLeft <= unsigned(fifoIn_Dout(9 downto 0));
                  drawingAreaTop  <= unsigned(fifoIn_Dout(18 downto 10));
                  
               elsif (cmdNew = 16#E4#) then -- Set Drawing Area bottom right (X2,Y2)
                  drawingAreaRight  <= unsigned(fifoIn_Dout(9 downto 0));
                  drawingAreaBottom <= unsigned(fifoIn_Dout(18 downto 10));
                  
               elsif (cmdNew = 16#E5#) then -- Set Drawing Offset (X,Y)
                  drawingOffsetX <= signed(fifoIn_Dout(10 downto 0));
                  drawingOffsetY <= signed(fifoIn_Dout(21 downto 11));
                  
               elsif (cmdNew = 16#E6#) then -- Mask Bit Setting
                  -- todo
                  
               end if;
            
            
            end if;
            
            if (proc_done = '1') then
               proc_idle            <= '1';
               GPUSTAT_ReadyRecCmd  <= '1';
            end if;
            
            if (softReset = '1') then
               drawMode               <= (others => '0');
               GPUSTAT_TextPageX      <= "0000";
               GPUSTAT_TextPageY      <= '0';
               GPUSTAT_Transparency   <= "00";
               GPUSTAT_TextPageColors <= "00";
               GPUSTAT_Dither         <= '0';
               GPUSTAT_DrawToDisplay  <= '0';
               GPUSTAT_SetMask        <= '0';
               GPUSTAT_ReadyRecCmd    <= '1';
               GPUSTAT_ReadySendVRAM  <= '0';
               GPUSTAT_ReadyRecDMA    <= '1';
            end if;
            
         end if;
         
      end if;
   end process; 
   
   proc_done        <= vramFill_done        or cpu2vram_done        or vram2vram_done        or line_done        or rect_done       ;
   proc_requestFifo <= vramFill_requestFifo or cpu2vram_requestFifo or vram2vram_requestFifo or line_requestFifo or rect_requestFifo;
   
   pixelStall <= fifoOut_NearFull;
   
   interlacedDrawing <= GPUSTAT_VertInterlace and GPUSTAT_VerRes and not GPUSTAT_DrawToDisplay;
   
   -- workers
   igpu_fillVram : entity work.gpu_fillVram
   port map
   (
      clk2x                => clk2x,     
      clk2xIndex           => clk2xIndex,
      ce                   => ce,        
      reset                => softreset,     
      
      proc_idle            => proc_idle,
      fifo_Valid           => fifoIn_Valid, 
      fifo_data            => fifoIn_Dout,
      requestFifo          => vramFill_requestFifo,
      done                 => vramFill_done,
      
      pixelStall           => pixelStall,
      pixelColor           => vramFill_pixelColor,
      pixelAddr            => vramFill_pixelAddr, 
      pixelWrite           => vramFill_pixelWrite
   );
   
   igpu_cpu2vram : entity work.gpu_cpu2vram
   port map
   (
      clk2x                => clk2x,     
      clk2xIndex           => clk2xIndex,
      ce                   => ce,        
      reset                => softreset,     
      
      proc_idle            => proc_idle,
      fifo_Valid           => fifoIn_Valid, 
      fifo_data            => fifoIn_Dout,
      requestFifo          => cpu2vram_requestFifo,
      done                 => cpu2vram_done,
      
      pixelStall           => pixelStall,
      pixelColor           => cpu2vram_pixelColor,
      pixelAddr            => cpu2vram_pixelAddr, 
      pixelWrite           => cpu2vram_pixelWrite
   );
   
   igpu_vram2vram : entity work.gpu_vram2vram
   port map
   (
      clk2x                => clk2x,     
      clk2xIndex           => clk2xIndex,
      ce                   => ce,        
      reset                => softreset,     
      
      GPUSTAT_SetMask      => GPUSTAT_SetMask,
      
      proc_idle            => proc_idle,
      fifo_Valid           => fifoIn_Valid, 
      fifo_data            => fifoIn_Dout,
      requestFifo          => vram2vram_requestFifo,
      done                 => vram2vram_done,
      
      requestVRAMEnable    => vram2vram_reqVRAMEnable,
      requestVRAMXPos      => vram2vram_reqVRAMXPos,  
      requestVRAMYPos      => vram2vram_reqVRAMYPos,  
      requestVRAMSize      => vram2vram_reqVRAMSize,  
      requestVRAMIdle      => reqVRAMIdle,
      requestVRAMDone      => reqVRAMDone,
      
      vramLineEna          => vram2vram_vramLineEna, 
      vramLineAddr         => vram2vram_vramLineAddr,
      vramLineData         => vramLineData,
      
      pixelEmpty           => fifoOut_Empty,
      pixelStall           => pixelStall,
      pixelColor           => vram2vram_pixelColor,
      pixelAddr            => vram2vram_pixelAddr, 
      pixelWrite           => vram2vram_pixelWrite
   );
   
   igpu_line : entity work.gpu_line
   port map
   (
      clk2x                => clk2x,     
      clk2xIndex           => clk2xIndex,
      ce                   => ce,        
      reset                => softreset,     
      
      interlacedDrawing    => interlacedDrawing,
      activeLineLSB        => activeLineLSB,    
      drawingOffsetX       => drawingOffsetX,   
      drawingOffsetY       => drawingOffsetY,   
      drawingAreaLeft      => drawingAreaLeft,  
      drawingAreaRight     => drawingAreaRight, 
      drawingAreaTop       => drawingAreaTop,   
      drawingAreaBottom    => drawingAreaBottom,
      
      div1                 => line_div(0), 
      div2                 => line_div(1), 
      div3                 => line_div(2), 
      div4                 => line_div(3), 
      div5                 => line_div(4), 
      div6                 => line_div(5), 
      
      pipeline_stall       => pipeline_stall,      
      pipeline_new         => line_pipeline_new,        
      pipeline_transparent => line_pipeline_transparent,
      pipeline_x           => line_pipeline_x,          
      pipeline_y           => line_pipeline_y,          
      pipeline_cr          => line_pipeline_cr,         
      pipeline_cg          => line_pipeline_cg,         
      pipeline_cb          => line_pipeline_cb,         
      
      proc_idle            => proc_idle,
      fifo_Valid           => fifoIn_Valid, 
      fifo_data            => fifoIn_Dout,
      requestFifo          => line_requestFifo,
      done                 => line_done,
      
      requestVRAMEnable    => line_reqVRAMEnable,
      requestVRAMXPos      => line_reqVRAMXPos,  
      requestVRAMYPos      => line_reqVRAMYPos,  
      requestVRAMSize      => line_reqVRAMSize,  
      requestVRAMIdle      => reqVRAMIdle,
      requestVRAMDone      => reqVRAMDone,
      
      vramLineEna          => line_vramLineEna, 
      vramLineAddr         => line_vramLineAddr
   );
   
   igpu_rect : entity work.gpu_rect
   port map
   (
      clk2x                => clk2x,     
      clk2xIndex           => clk2xIndex,
      ce                   => ce,        
      reset                => softreset,     
      
      interlacedDrawing    => interlacedDrawing,
      activeLineLSB        => activeLineLSB,    
      drawingOffsetX       => drawingOffsetX,   
      drawingOffsetY       => drawingOffsetY,   
      drawingAreaLeft      => drawingAreaLeft,  
      drawingAreaRight     => drawingAreaRight, 
      drawingAreaTop       => drawingAreaTop,   
      drawingAreaBottom    => drawingAreaBottom,
      
      pipeline_stall       => pipeline_stall,      
      pipeline_new         => rect_pipeline_new,        
      pipeline_texture     => rect_pipeline_texture,
      pipeline_transparent => rect_pipeline_transparent,
      pipeline_rawTexture  => rect_pipeline_rawTexture,
      pipeline_x           => rect_pipeline_x,          
      pipeline_y           => rect_pipeline_y,          
      pipeline_cr          => rect_pipeline_cr,         
      pipeline_cg          => rect_pipeline_cg,         
      pipeline_cb          => rect_pipeline_cb,         
      pipeline_u           => rect_pipeline_u,         
      pipeline_v           => rect_pipeline_v,         
      
      proc_idle            => proc_idle,
      fifo_Valid           => fifoIn_Valid, 
      fifo_data            => fifoIn_Dout,
      requestFifo          => rect_requestFifo,
      done                 => rect_done,
      
      requestVRAMEnable    => rect_reqVRAMEnable,
      requestVRAMXPos      => rect_reqVRAMXPos,  
      requestVRAMYPos      => rect_reqVRAMYPos,  
      requestVRAMSize      => rect_reqVRAMSize,  
      requestVRAMIdle      => reqVRAMIdle,
      requestVRAMDone      => reqVRAMDone,
      
      vramLineEna          => rect_vramLineEna, 
      vramLineAddr         => rect_vramLineAddr
   );
   
   pipeline_new         <= line_pipeline_new         or rect_pipeline_new        ;       
   pipeline_texture     <= '0'                       or rect_pipeline_texture    ;
   pipeline_transparent <= line_pipeline_transparent or rect_pipeline_transparent;          
   pipeline_rawTexture  <= '0'                       or rect_pipeline_rawTexture ;         
   pipeline_x           <= line_pipeline_x           or rect_pipeline_x          ;       
   pipeline_y           <= line_pipeline_y           or rect_pipeline_y          ;     
   pipeline_cr          <= line_pipeline_cr          or rect_pipeline_cr         ;
   pipeline_cg          <= line_pipeline_cg          or rect_pipeline_cg         ;
   pipeline_cb          <= line_pipeline_cb          or rect_pipeline_cb         ;
   pipeline_u           <= x"00"                     or rect_pipeline_u          ;
   pipeline_v           <= x"00"                     or rect_pipeline_v          ;
   
   igpu_pixelpipeline : entity work.gpu_pixelpipeline
   port map
   (
      clk2x                => clk2x,     
      clk2xIndex           => clk2xIndex,
      ce                   => ce,        
      reset                => softreset,  

      transparencyMode     => drawMode(6 downto 5),
      
      pipeline_stall       => pipeline_stall,      
      pipeline_new         => pipeline_new,        
      pipeline_texture     => pipeline_texture,    
      pipeline_transparent => pipeline_transparent,
      pipeline_rawTexture  => pipeline_rawTexture, 
      pipeline_x           => pipeline_x,          
      pipeline_y           => pipeline_y,          
      pipeline_cr          => pipeline_cr,         
      pipeline_cg          => pipeline_cg,         
      pipeline_cb          => pipeline_cb,         
      pipeline_u           => pipeline_u,          
      pipeline_v           => pipeline_v,          
      
      requestVRAMEnable    => pipeline_reqVRAMEnable,
      requestVRAMXPos      => pipeline_reqVRAMXPos,  
      requestVRAMYPos      => pipeline_reqVRAMYPos,  
      requestVRAMSize      => pipeline_reqVRAMSize,  
      requestVRAMIdle      => reqVRAMIdle,
      requestVRAMDone      => reqVRAMDone,
      
      vramLineData         => vramLineData,
      
      pixelStall           => pixelStall,
      pixelColor           => pipeline_pixelColor,
      pixelAddr            => pipeline_pixelAddr, 
      pixelWrite           => pipeline_pixelWrite
   );
   
   gdividers: for i in 0 to 5 generate
   begin
      idivider : entity work.divider
      port map
      (
         clk       => clk2x,      
         start     => line_div(i).start,
         done      => line_div(i).done,          
         dividend  => line_div(i).dividend, 
         divisor   => line_div(i).divisor,  
         quotient  => line_div(i).quotient, 
         remainder => line_div(i).remainder
      );
   end generate;
   
   pixelColor <= vramFill_pixelColor or cpu2vram_pixelColor or vram2vram_pixelColor or pipeline_pixelColor;
   pixelAddr  <= vramFill_pixelAddr  or cpu2vram_pixelAddr  or vram2vram_pixelAddr  or pipeline_pixelAddr ;
   pixelWrite <= vramFill_pixelWrite or cpu2vram_pixelWrite or vram2vram_pixelWrite or pipeline_pixelWrite;
   
   -- pixel writing fifo
   iSyncFifo_OUT: entity mem.SyncFifo
   generic map
   (
      SIZE             => 256,
      DATAWIDTH        => 85,  -- 64bit data, 17 bit address + 4bit word enable
      NEARFULLDISTANCE => 250
   )
   port map
   ( 
      clk      => clk2x,
      reset    => fifoOut_reset,  
      Din      => fifoOut_Din,     
      Wr       => fifoOut_Wr,      
      Full     => fifoOut_Full,    
      NearFull => fifoOut_NearFull,
      Dout     => fifoOut_Dout,    
      Rd       => fifoOut_Rd,      
      Empty    => fifoOut_Empty   
   );
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
      
         fifoOut_Wr  <= '0';
         fifoOut_Din <= pixel64wordEna & pixel64Addr & pixel64data;
      
         if (reset = '1') then
            
            pixel64filled <= '0';
            
         elsif (ce = '1') then
         
            if (pixelWrite = '1') then
            
               pixel64timeout <= 15;
            
               if (pixel64filled = '0' or pixelAddr(19 downto 3) /= unsigned(pixel64Addr)) then
               
                  fifoOut_Wr <= pixel64filled;
               
                  pixel64Addr <= std_logic_vector(pixelAddr(19 downto 3));
                  case (pixelAddr(2 downto 1)) is
                     when "00" => pixel64data(15 downto  0) <= pixelColor; pixel64wordEna <= "0001";
                     when "01" => pixel64data(31 downto 16) <= pixelColor; pixel64wordEna <= "0010";
                     when "10" => pixel64data(47 downto 32) <= pixelColor; pixel64wordEna <= "0100";
                     when "11" => pixel64data(63 downto 48) <= pixelColor; pixel64wordEna <= "1000";
                     when others => null;
                  end case;
                  
                  pixel64filled <= '1';
               
               else
                  
                  case (pixelAddr(2 downto 1)) is
                     when "00" => pixel64data(15 downto  0) <= pixelColor; pixel64wordEna(0) <= '1';
                     when "01" => pixel64data(31 downto 16) <= pixelColor; pixel64wordEna(1) <= '1';
                     when "10" => pixel64data(47 downto 32) <= pixelColor; pixel64wordEna(2) <= '1';
                     when "11" => pixel64data(63 downto 48) <= pixelColor; pixel64wordEna(3) <= '1';
                     when others => null;
                  end case;

               end if;
            
            elsif (pixel64timeout > 0) then
            
               pixel64timeout <= pixel64timeout - 1;
               if (pixel64timeout = 1) then
                  pixel64filled  <= '0';
                  fifoOut_Wr     <= '1';
               end if;
               
            end if;
            
         end if;

      end if;
   end process;
   
   fifoOut_Rd <= '1' when (ce = '1' and vramState = IDLE and vram_BUSY = '0' and fifoOut_Empty = '0' and reqVRAMEnable = '0') else '0';
   
   reqVRAMIdle <= '1' when vramState = IDLE else '0';
   
   reqVRAMEnable <= vram2vram_reqVRAMEnable or line_reqVRAMEnable or rect_reqVRAMEnable or pipeline_reqVRAMEnable;
   reqVRAMXPos   <= vram2vram_reqVRAMXPos   or line_reqVRAMXPos   or rect_reqVRAMXPos   or pipeline_reqVRAMXPos  ;  
   reqVRAMYPos   <= vram2vram_reqVRAMYPos   or line_reqVRAMYPos   or rect_reqVRAMYPos   or pipeline_reqVRAMYPos  ;  
   reqVRAMSize   <= vram2vram_reqVRAMSize   or line_reqVRAMSize   or rect_reqVRAMSize   or pipeline_reqVRAMSize  ;  
   
   vramLineAddr  <= vram2vram_vramLineAddr when vram2vram_vramLineEna else 
                    line_vramLineAddr  when line_vramLineEna else
                    rect_vramLineAddr  when rect_vramLineEna else
                    (others => '0');
   
   -- vram access
   process (clk2x)
      variable reqVRAMSizeRounded : unsigned(10 downto 0);
   begin
      if rising_edge(clk2x) then
      
         if (vram_BUSY = '0') then
            vram_WE <= '0';
            vram_RD <= '0';
         end if;
         
         reqVRAMDone <= '0';
         
         if (reset = '1') then
            
            vramState <= IDLE;
            
         elsif (ce = '1') then
         
            case (vramState) is
               when IDLE =>
                  if (reqVRAMEnable = '1') then
                     reqVRAMSizeRounded := reqVRAMSize;
                     if (reqVRAMSize(1 downto 0) /= "00") then -- round up read size to full 4*16bit
                        reqVRAMSizeRounded(10 downto 2) := reqVRAMSizeRounded(10 downto 2) + 1;
                     end if;
                     if ((to_integer(reqVRAMXPos(1 downto 0)) + to_integer(reqVRAMSize(1 downto 0))) > 3) then -- increase read size by 1 if 4 word boundary is crossed
                        reqVRAMSizeRounded(10 downto 2) := reqVRAMSizeRounded(10 downto 2) + 1;
                     end if;
                     vramState     <= READVRAM;
                     vram_ADDR     <= std_logic_vector(reqVRAMYPos) & std_logic_vector(reqVRAMXPos(9 downto 2)) & "000";
                     vram_RD       <= '1';
                     reqVRAMaddr   <= reqVRAMXPos(9 downto 2);
                     if (reqVRAMSizeRounded > 512) then
                        vram_BURSTCNT <= x"80";
                        reqVRAMremain <= x"80" - 1;
                        reqVRAMnext   <= reqVRAMSizeRounded(8 downto 2);
                     else
                        vram_BURSTCNT <= std_logic_vector(reqVRAMSizeRounded(9 downto 2));
                        reqVRAMremain <= reqVRAMSizeRounded(9 downto 2) - 1;
                        reqVRAMnext   <= (others => '0');
                     end if;
                  elsif (fifoOut_Empty = '0') then
                     vramState <= WRITEPIXEL;
                  end if;
                  
               when WRITEPIXEL =>
                  vramState     <= IDLE;
                  vram_WE       <= '1';
                  vram_ADDR     <= fifoOut_Dout(80 downto 64) & "000";
                  vram_BE       <= fifoOut_Dout(84) & fifoOut_Dout(84) & fifoOut_Dout(83) & fifoOut_Dout(83) & fifoOut_Dout(82) & fifoOut_Dout(82) & fifoOut_Dout(81) & fifoOut_Dout(81);
                  vram_DIN      <= fifoOut_Dout(63 downto 0);
                  vram_BURSTCNT <= x"01";
            
               when READVRAM =>
                  if (vram_DOUT_READY = '1') then
                     reqVRAMaddr <= reqVRAMaddr + 1;
                     if (reqVRAMremain > 0) then
                        reqVRAMremain <= reqVRAMremain - 1;
                     else
                        if (reqVRAMnext > 0) then
                           vram_ADDR(10) <= '1';
                           vram_RD       <= '1';
                           vram_BURSTCNT <= '0' & std_logic_vector(reqVRAMnext);
                        else
                           vramState   <= IDLE;
                           reqVRAMDone <= '1';
                        end if;
                     end if;
                  end if;
            
            end case;
            
         end if;

      end if;
   end process;
   
   ilineram: entity work.dpram_dif
   generic map 
   ( 
      addr_width_a  => 8,
      data_width_a  => 64,
      addr_width_b  => 10,
      data_width_b  => 16
   )
   port map
   (
      clock       => clk2x,
      
      address_a   => std_logic_vector(reqVRAMaddr),
      data_a      => vram_DOUT,
      wren_a      => vram_DOUT_READY,
      
      address_b   => std_logic_vector(vramLineAddr),
      data_b      => x"0000",
      wren_b      => '0',
      q_b         => vramLineData
   );

end architecture;





