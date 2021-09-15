library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity dma is
   port 
   (
      clk1x                : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      cpuPaused            : in  std_logic;
      dmaOn                : out std_logic;
      irqOut               : out std_logic := '0';
      
      ram_refresh          : out std_logic;
      ram_dataWrite        : out std_logic_vector(31 downto 0) := (others => '0');
      ram_dataRead         : in  std_logic_vector(127 downto 0);
      ram_Adr              : out std_logic_vector(22 downto 0) := (others => '0');
      ram_be               : out std_logic_vector(3 downto 0) := (others => '0');
      ram_rnw              : out std_logic := '0';
      ram_ena              : out std_logic := '0';
      ram_128              : out std_logic := '0';
      ram_done             : in  std_logic;
      ram_reqprocessed     : in  std_logic;
      
      gpu_dmaRequest       : in  std_logic;
      DMA_GPU_writeEna     : out std_logic := '0';
      DMA_GPU_readEna      : out std_logic := '0';
      DMA_GPU_write        : out std_logic_vector(31 downto 0);
      DMA_GPU_read         : in  std_logic_vector(31 downto 0);
      
      bus_addr             : in  unsigned(6 downto 0); 
      bus_dataWrite        : in  std_logic_vector(31 downto 0);
      bus_read             : in  std_logic;
      bus_write            : in  std_logic;
      bus_dataRead         : out std_logic_vector(31 downto 0)
   );
end entity;

architecture arch of dma is

   type tdmaState is
   (
      OFF,
      WAITING,
      READHEADER,
      WAITREAD,
      WORKING,
      STOPPING,
      PAUSING,
      TIMEUP,
      GPUBUSY
   );
   signal dmaState : tdmaState := OFF;

   type dmaRecord is record
      D_MADR            : unsigned(23 downto 0);
      D_BCR             : unsigned(31 downto 0);
      D_CHCR            : unsigned(31 downto 0);
      request           : std_logic;
      timeupPending     : std_logic;
      requestsPending   : std_logic;
   end record;
  
   type tdmaArray is array (0 to 6) of dmaRecord;
   signal dmaArray : tdmaArray;
  
   signal DPCR          : unsigned(31 downto 0);
   signal DICR          : unsigned(31 downto 0);
   signal DICR_readback : unsigned(31 downto 0);
   signal DICR_IRQs     : unsigned(6 downto 0);
   
   signal triggerDMA    : std_logic_vector(6 downto 0);
   
   signal isOn          : std_logic;
   signal activeChannel : integer range 0 to 6;
   signal paused        : std_logic;
   signal gpupaused     : std_logic;
   signal waitcnt       : integer range 0 to 15;
   signal dmaTime       : integer range 0 to 65535;
   signal wordcount     : unsigned(16 downto 0);
   signal toDevice      : std_logic;
   signal directionNeg  : std_logic;
   signal nextAddr      : std_logic_vector(23 downto 0);
   signal blocksleft    : unsigned(15 downto 0);
   signal dmacount      : unsigned(9 downto 0);
   
   signal autoread      : std_logic := '0';
   signal readcount     : unsigned(9 downto 0);
   signal readsize      : unsigned(9 downto 0);
   signal firstword     : std_logic := '0';

   signal dataNext      : std_logic_vector(95 downto 0);
   signal dataCount     : integer range 0 to 3 := 0;
   signal firstsize     : integer range 0 to 3 := 0;
   
   signal fifo_reset    : std_logic := '0';
   signal fifo_Din      : std_logic_vector(31 downto 0);
   signal fifo_Wr       : std_logic; 
   signal fifo_Full     : std_logic;
   signal fifo_NearFull : std_logic;
   signal fifo_Dout     : std_logic_vector(31 downto 0);
   signal fifo_Rd       : std_logic;
   signal fifo_Empty    : std_logic;
   signal fifo_Valid    : std_logic;
  
begin 

   dmaOn <= '1' when (dmaState = WAITING or dmaState = READHEADER or dmaState = WAITREAD or dmaState = WORKING) else '0';

   ram_refresh <= '1' when (dmaState = WAITING and cpuPaused = '1' and waitcnt = 9) else '0';
   ram_be      <= "1111";
   ram_128     <= '1';

   DICR_readback( 5 downto  0) <= DICR( 5 downto 0);
   DICR_readback(14 downto  6) <= "000000000";
   DICR_readback(23 downto 15) <= DICR(23 downto 15);
   DICR_readback(30 downto 24) <= DICR_IRQs;
   DICR_readback(31)           <= irqOut;
   
   
   DMA_GPU_writeEna <= '1' when (dmaState = working and fifo_Valid = '1' and activeChannel = 2 and toDevice = '1') else '0'; 
   DMA_GPU_write    <= fifo_Dout;

   process (clk1x)
      variable channel        : integer range 0 to 7;
      variable triggerNew     : std_logic;
      variable triggerchannel : integer range 0 to 6;
   begin
      if rising_edge(clk1x) then
      
         fifo_reset <= '0';
      
         if (reset = '1') then
         
            dmaState <= OFF;
            
            irqOut   <= '0';
         
            for i in 0 to 6 loop
               dmaArray(i).D_MADR            <= (others => '0');
               dmaArray(i).D_BCR             <= (others => '0');
               dmaArray(i).D_CHCR            <= (others => '0');
               dmaArray(i).request           <= '0';
               dmaArray(i).timeupPending     <= '0';
               dmaArray(i).requestsPending   <= '0';
            end loop;
            
            DPCR           <= x"07654321";
            DICR           <= (others => '0');
            DICR_IRQs      <= (others => '0');
               
            triggerDMA     <= (others => '0');
            isOn           <= '0';
            activeChannel  <= 0;
            paused         <= '0';
            gpupaused      <= '0';
            waitcnt        <= 0;
            dmaTime        <= 0;
            
            autoread       <= '0';
            
            fifo_reset     <= '1';
            dataCount      <= 0;

         elsif (ce = '1') then
         
            ram_ena    <= '0';
         
            triggerDMA <= (others => '0');
         
            bus_dataRead <= (others => '0');

            channel := to_integer(unsigned(bus_addr(6 downto 4)));
            
            DMA_GPU_readEna  <= '0';
            
            dmaArray(0).request <= '0';
            dmaArray(1).request <= '0';
            dmaArray(2).request <= gpu_dmaRequest;
            dmaArray(3).request <= '0';
            dmaArray(4).request <= '0';
            dmaArray(5).request <= '0';
            dmaArray(6).request <= '0';
            
            -- bus read
            if (bus_read = '1') then
               if (channel < 7) then
                  case (bus_addr(3 downto 2)) is
                     when "00" => bus_dataRead <= x"00" & std_logic_vector(dmaArray(channel).D_MADR);
                     when "01" => bus_dataRead <= std_logic_vector(dmaArray(channel).D_BCR); 
                     when "10" => bus_dataRead <= std_logic_vector(dmaArray(channel).D_CHCR);
                     when others => bus_dataRead <= (others => '1');
                  end case;
               else
                  case (bus_addr(3 downto 2)) is
                     when "00" => bus_dataRead <= std_logic_vector(DPCR);
                     when "01" => bus_dataRead <= std_logic_vector(DICR_readback); 
                     when others => bus_dataRead <= (others => '1');
                  end case;
               end if;
            end if;

            -- bus write
            if (bus_write = '1') then
               if (channel < 7) then
                  case (bus_addr(3 downto 2)) is
                     when "00" => dmaArray(channel).D_MADR <= unsigned(bus_dataWrite(23 downto 0));
                     when "01" => dmaArray(channel).D_BCR  <= unsigned(bus_dataWrite);
                     when "10" =>  -- todo: channel 6 has only 3 r/w bits
                        dmaArray(channel).D_CHCR( 1 downto  0) <= unsigned(bus_dataWrite( 1 downto  0));
                        dmaArray(channel).D_CHCR(10 downto  8) <= unsigned(bus_dataWrite(10 downto  8));
                        dmaArray(channel).D_CHCR(18 downto 16) <= unsigned(bus_dataWrite(18 downto 16));
                        dmaArray(channel).D_CHCR(22 downto 20) <= unsigned(bus_dataWrite(22 downto 20));
                        dmaArray(channel).D_CHCR(          24) <= bus_dataWrite(24);
                        dmaArray(channel).D_CHCR(30 downto 28) <= unsigned(bus_dataWrite(30 downto 28));
                        if (dmaArray(channel).request = '1') then
                           triggerDMA(channel) <= '1';
                        end if;
                     when others => null;
                  end case;
               else
                  case (bus_addr(3 downto 2)) is
                     when "00" => 
                        DPCR       <= unsigned(bus_dataWrite);
                        triggerDMA <= (others => '1'); -- really?
                     when "01" => 
                        DICR <= unsigned(bus_dataWrite);
                        if (bus_dataWrite(15) = '1') then
                           irqOut <= '1';
                        end if;
                     when others => null;
                  end case;
               end if;
               
            end if;
            
            -- trigger
            triggerNew     := '0';
            triggerchannel := 0;
            for i in 0 to 6 loop
               if (triggerDMA(i) = '1') then
                  if (DPCR((i * 4) + 3) = '1') then -- enable
                     if (dmaArray(i).D_CHCR(24) = '1') then -- start/busy
                        if (isOn = '0' or activeChannel /= i) then
                        
                           if (dmaState = GPUBUSY) then
                              gpupaused <= '1';
                              paused    <= '0';
                           end if;
                           
                           if (dmaState = TIMEUP) then
                              dmaArray(activeChannel).timeupPending <= '1';
                              paused    <= '0';
                           end if;
                           
                           if (dmaState /= OFF and dmaState /= TIMEUP and dmaState = TIMEUP) then
                              dmaArray(i).requestsPending <= '1';
                           else
                              -- todo : priority
                              triggerNew     := '1';
                              triggerchannel := i;
                           end if;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
            
            if (triggerNew = '1') then
               dmaArray(triggerchannel).requestsPending <= '0';
               dmaArray(triggerchannel).timeupPending   <= '0';
               dmaArray(triggerchannel).D_CHCR(28)      <= '0';
               
               dmaState      <= WAITING;
               waitcnt       <= 9;
               isOn          <= '1';
               activeChannel <= triggerchannel;
               dmaTime       <= 0;
            end if;
            
            
            case (dmaState) is
            
               when OFF => null;
               
               when WAITING =>
                  if (waitcnt > 0 and cpuPaused = '1') then
                     waitcnt <= waitcnt - 1;
                  end if;
                  if (waitcnt = 8) then
                     dmacount     <= (others => '0');
                     toDevice     <= dmaArray(activeChannel).D_CHCR(0);
                     if (dmaArray(activeChannel).D_CHCR(0) = '1') then
                        ram_rnw     <= '1';
                        ram_ena     <= '1';
                        ram_Adr     <= "00" & std_logic_vector(dmaArray(activeChannel).D_MADR(20 downto 2)) & "00";
                        autoread    <= '1';
                     end if;
                     directionNeg <= '0';
                     if (dmaArray(activeChannel).D_CHCR(10) = '0' and dmaArray(activeChannel).D_CHCR(1) = '1') then
                        directionNeg <= '1';
                     end if;                         
                  end if;
                  if (waitcnt = 1) then
                     if (fifo_Empty = '1') then
                        waitcnt <= waitcnt;
                     else
                        case (dmaArray(activeChannel).D_CHCR(10 downto 9)) is
                           when "00" => -- manual
                              dmaState    <= WORKING;
                           
                           when "01" => -- request
                              dmaState    <= WORKING;
                           
                           when "10" => -- linked list
                              dmaState    <= READHEADER;
                           
                           when others => 
                              dmaState <= OFF;
                              isOn     <= '0';
                        end case;
                     end if;
                  end if;
               
               when READHEADER =>
                  dmacount  <= dmacount + 1;
                  nextAddr  <= fifo_Dout(23 downto 0);
                  if (unsigned(fifo_Dout(31 downto 24)) > 0) then
                     dmaArray(activeChannel).D_MADR <= dmaArray(activeChannel).D_MADR + 4;
                     dmaState  <= WAITREAD;
                     waitcnt   <= 4;              
                  elsif (fifo_Dout(23) = '1' or fifo_Dout(23 downto 0) = x"000000" or dmaArray(activeChannel).D_CHCR(0) = '0') then
                     dmaState <= STOPPING;
                     autoread <= '0';
                  else
                     dmaArray(activeChannel).D_MADR <= unsigned(fifo_Dout(23 downto 0));
                     waitcnt   <= 9;
                     dmaState  <= WAITING;
                     autoread  <= '0';
                     -- todo: add timeup check
                  end if;  
               
               when WAITREAD =>
                  if (waitcnt > 0) then
                     waitcnt <= waitcnt - 1;
                  end if;
                  if (waitcnt = 1) then
                     dmaState    <= WORKING;
                  end if;
               
               when WORKING =>
                  if (fifo_Valid = '1') then
                     dmacount    <= dmacount + 1;
                     case (activeChannel) is
                     
                        when 2 =>
                           if (toDevice = '0') then
                              report "GPU DMA read not implemented" severity failure; 
                           end if;
                     
                        when others => report "DMA channel not implemented" severity failure; 
                     end case;
                     
                     if (dmaArray(activeChannel).D_CHCR(10) = '0' and directionNeg = '1')  then 
                        dmaArray(activeChannel).D_MADR <= dmaArray(activeChannel).D_MADR - 4;
                     else
                        dmaArray(activeChannel).D_MADR <= dmaArray(activeChannel).D_MADR + 4;
                     end if;
                  
                     wordcount <= wordcount - 1;
                     if (wordcount <= 1) then
                        case (dmaArray(activeChannel).D_CHCR(10 downto 9)) is
                           when "00" => -- manual
                           
                           when "01" => -- request
                              dmaArray(activeChannel).D_BCR(31 downto 16) <= blocksleft;
                              blocksleft <= blocksleft - 1;
                              if (blocksleft = 0) then
                                 dmaState <= STOPPING;
                                 autoread <= '0';
                              else
                                 wordcount  <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                                 if (dmaArray(activeChannel).request = '0') then
                                    dmaState <= PAUSING;
                                    autoread <= '0';
                                 elsif (dmacount + dmaArray(activeChannel).D_BCR(15 downto 0) >= 1000) then
                                    dmaState <= WAITING;
                                    waitcnt  <= 9;
                                    autoread <= '0';
                                 end if;
                                 -- todo timeup check
                              end if;
                           
                           when "10" => -- linked list
                              dmaArray(activeChannel).D_MADR <= unsigned(nextAddr);
                              if (nextAddr(23) = '1') then
                                 dmaState <= STOPPING;
                                 autoread <= '0';
                              else
                                 -- todo add timeup
                                 if (gpu_dmaRequest = '1') then
                                    dmaState <= WAITING;
                                    waitcnt  <= 10;
                                    autoread <= '0';
                                 else
                                    dmaState <= GPUBUSY;
                                    paused   <= '1';
                                    autoread <= '0';
                                 end if;
                              end if;
                           
                           when others => null;
                        end case;
                     end if;
                  end if;
               
               when STOPPING =>
                  dmaState <= OFF;
                  isOn     <= '0';
                  dmaArray(activeChannel).D_CHCR(24) <= '0';
                  isOn <= '0';
                  if (DICR(16 + activeChannel) = '1') then
                     DICR(24 + activeChannel) <= '1';
                     if (DICR(23) = '1') then
                        irqOut <= '1';
                     end if;
                  end if;
                  
                  -- todo: add check for gpubusy
                  
                  -- todo: add check for  pending requests
                  
               
               when PAUSING =>
               
               when TIMEUP =>
               
               when GPUBUSY =>
                  if (gpu_dmaRequest = '1') then
                     dmaState <= WAITING;
                     waitcnt  <= 9;
                     autoread <= '0';
                     paused <= '0';
                  end if;
            
            end case;
            
         end if;
         
         if (ram_done = '1') then
            dataNext  <= ram_dataRead(127 downto 32);
            dataCount <= 3;
         
            readcount <= readcount + 1;
            if (firstword = '1') then
               firstword <= '0';
               dataCount <= firstsize;
               case (dmaArray(activeChannel).D_CHCR(10 downto 9)) is
                  when "00" => -- manual
                     if (dmaArray(activeChannel).D_BCR(15 downto 0) = 0) then
                        wordcount <= '1' & x"0000";
                        readsize  <= to_unsigned(1000, 10);
                     else
                        wordcount <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                        if (dmaArray(activeChannel).D_BCR(15 downto 0) < 1000) then
                           readsize <= dmaArray(activeChannel).D_BCR(9 downto 0);
                        else
                           readsize <= to_unsigned(1000, 10);
                        end if;
                     end if;
                  
                  when "01" => -- request
                     blocksleft  <= dmaArray(activeChannel).D_BCR(31 downto 16) - 1;
                     wordcount   <= '0' & dmaArray(activeChannel).D_BCR(15 downto 0);
                     if ((dmaArray(activeChannel).D_BCR(15 downto 0) * dmaArray(activeChannel).D_BCR(31 downto 16)) < 1000) then
                        readsize <= to_unsigned(to_integer(dmaArray(activeChannel).D_BCR(15 downto 0) * dmaArray(activeChannel).D_BCR(31 downto 16)), 10);
                     else
                        readsize <= to_unsigned(1000, 10);
                     end if;
                  
                  when "10" => -- linked list
                     wordcount <= "0" & x"00" & unsigned(ram_dataRead(31 downto 24)); 
                     readsize  <= to_unsigned(to_integer(unsigned(ram_dataRead(31 downto 24))) + 1, 10);
                  
                  when others => null;
               end case;
            end if;
         end if;
         
         if (ram_reqprocessed = '1' and autoread = '1') then
            if (readcount + 4 + dataCount < readsize) then
               ram_ena <= '1';
            end if;
            if (directionNeg = '1') then
               ram_Adr <= std_logic_vector((unsigned(ram_Adr(22 downto 4)) & "0000") - 16); 
            else
               ram_Adr <= std_logic_vector((unsigned(ram_Adr(22 downto 4)) & "0000") + 16); 
            end if;
         end if;
         
         if (dmaState = WAITING and waitcnt = 8) then
            readsize    <= to_unsigned(8, 10); -- get the transfer pipeline running
            readcount   <= (others => '0');
            firstword   <= '1';
            firstsize   <= to_integer(3 - dmaArray(activeChannel).D_MADR(3 downto 2));
            fifo_reset  <= '1';
            dataCount   <= 0;
         elsif (dataCount > 0) then
            readcount <= readcount + 1;
            dataCount <= dataCount- 1;
            dataNext  <= x"00000000" & dataNext(95 downto 32);
         end if;
         
         fifo_Valid <= fifo_Rd;
         
      end if;
   end process;
   
   fifo_Wr  <= '1' when (ram_done = '1' or dataCount > 0) else '0'; 
   
   fifo_Din <= ram_dataRead(31 downto 0) when ram_done = '1' else
               dataNext(31 downto 0);
   
   
   fifo_Rd <= '1' when (fifo_Empty = '0' and ((dmaState = WAITING and waitcnt = 1) or (dmaState = WAITREAD and waitcnt = 1) or dmaState = working)) else '0';

   
   iDMAFifo: entity mem.SyncFifo
   generic map
   (
      SIZE             => 64,
      DATAWIDTH        => 32,
      NEARFULLDISTANCE => 32
   )
   port map
   ( 
      clk      => clk1x,
      reset    => fifo_reset,  
      Din      => fifo_Din,     
      Wr       => fifo_Wr,      
      Full     => fifo_Full,    
      NearFull => fifo_NearFull,
      Dout     => fifo_Dout,    
      Rd       => fifo_Rd,      
      Empty    => fifo_Empty   
   );
   

end architecture;





