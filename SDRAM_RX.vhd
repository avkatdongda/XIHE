----------------------------------------------------------------------------------
-- Company:         CIOMP
-- Engineer:        WangZheng
-- Create Date:     17:11:58 01/06/2020
-- Module Name:     SDRAM_RX - Behavioral
-- Project Name:    SEN_IMA
-- Target Devices:  Virtex-4 xqr4vsx55-10cf1140
-- Tool versions:   ISE 14.7
-- Description:     sdram_rx receive the 4 channel fifo image data into a rx fifo
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.STD_LOGIC_ARITH.all;
use IEEE.STD_LOGIC_UNSIGNED.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity SDRAM_RX is
    port (
        ---------CLOCKING---------
        Clk_Sdr                     : in  STD_LOGIC;                            -- sdram W/R clk 100MHz
        Rst_Sdr                     : in  STD_LOGIC;                            -- Clk_Sdr correspond rst signal
        ---------SERIAL_CMD---------
        Store_Status                : out STD_LOGIC_VECTOR (1 downto 0);        -- store status, "00" is initial, "10" is working, "01" none
        Gain_Mode                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- sensor Gain_Mode HG/LG 11H/22H, default 11H
        ---------NOF_CTL---------
        Nor_FIFO_Req                : out STD_LOGIC;                            -- nor fifo receive request
        Nor_FIFO_q                  : in  STD_LOGIC_VECTOR (15 downto 0);       -- nor fifo output 16bit data
        Nor_FIFO_Prog_Empty         : in  STD_LOGIC;                            -- nor fifo fifo prog empty
        ---------SEN_DRIVE---------
        Image_Out                   : in  STD_LOGIC;                            -- pull high when the image's output is valid
        ---------IMA_RX---------
        RX_FIFO_q_Chan1             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_q_Chan2             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_q_Chan3             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_q_Chan4             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_q_Chan5             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_q_Chan6             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_q_Chan7             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_q_Chan8             : in  STD_LOGIC_VECTOR (15 downto 0);
        RX_FIFO_Req_Chan1           : out STD_LOGIC;
        RX_FIFO_Req_Chan2           : out STD_LOGIC;
        RX_FIFO_Req_Chan3           : out STD_LOGIC;
        RX_FIFO_Req_Chan4           : out STD_LOGIC;
        RX_FIFO_Req_Chan5           : out STD_LOGIC;
        RX_FIFO_Req_Chan6           : out STD_LOGIC;
        RX_FIFO_Req_Chan7           : out STD_LOGIC;
        RX_FIFO_Req_Chan8           : out STD_LOGIC;
        RX_FIFO_Prog_Chan1          : in  STD_LOGIC;
        RX_FIFO_Prog_Chan5          : in  STD_LOGIC;
        ---------IMA_GEN---------
        Self_Image_Out              : in  STD_LOGIC;                            -- pull high when the selfcheck image's output is valid
        ---------SDRAM_DRIVE---------
        Sd_Wr_Ack                   : in  STD_LOGIC;                            -- the acknowledge signal after receiving Sd_Wr
        Sd_Wr_End                   : in  STD_LOGIC;                            -- the end signal of sdram one row data
        Sd_Wr                       : out STD_LOGIC;                            -- the enable signal of starting writing
        Sd_Wr_Cs                    : out STD_LOGIC_VECTOR (7 downto 0);        -- sdram chip select signal, write mode
        Sd_Wr_Addr                  : out STD_LOGIC_VECTOR (24 downto 0);       -- BA(2)+ROW(13)+COL(10) address, COL is.all 0, BA is chip selection, 00 01 10 11, correspond 8192 row. 2k*2k storage 1 selection. 
        Sd_Wr_Data                  : out STD_LOGIC_VECTOR (15 downto 0));      -- the data signal of outputting
end SDRAM_RX;

architecture Behavioral of SDRAM_RX is

    -- reg
    signal  Image_Out_r1            : STD_LOGIC;
    signal  Image_Out_r2            : STD_LOGIC;
    signal  Self_Image_Out_r1       : STD_LOGIC;
    signal  Self_Image_Out_r2       : STD_LOGIC;
    signal  Cs_Sign                 : STD_LOGIC;                                -- '0' norflash data, '1' cmos data
    signal  Gain_Mode_r1            : STD_LOGIC_VECTOR (7 downto 0);
    signal  Gain_Mode_r2            : STD_LOGIC_VECTOR (7 downto 0);
    signal  Addr_Ba                 : STD_LOGIC_VECTOR (1 downto 0);            -- BA addr register
    signal  Addr_Row                : STD_LOGIC_VECTOR (12 downto 0);           -- ROW addr register
    signal  Addr_Col                : STD_LOGIC_VECTOR (9 downto 0);            -- COL addr register
    signal  Sd_Wr_Cs_r              : STD_LOGIC_VECTOR (7 downto 0);            -- CS addr register, nor data 7F, cmos data BF~FE
    -- SDRAM_RX_FIFO
    signal  FIFO_Rst                : STD_LOGIC;
    signal  SDRX_FIFO_d             : STD_LOGIC_VECTOR (15 downto 0);
    signal  SDRX_FIFO_Wr            : STD_LOGIC;
    signal  SDRX_FIFO_Empty         : STD_LOGIC;
    signal  SDRX_FIFO_Req           : STD_LOGIC;
    signal  SDRX_FIFO_Prog_Empty    : STD_LOGIC;
    -- cnt
    signal  data_cnt                : integer range 0 to 1023;                  -- count data from 4 channel fifo and nor fifo to sdram rx fifo
    signal  sd_cnt                  : integer range 0 to 1024;                  -- count data from sdram rx fifo to sdram
    signal  row_cnt                 : integer range 0 to 2048;                  -- count row from sdram rx fifo to sdram
    -- fsm
    -- sdram rx fifo state
    type    Fsm_Sd_Rx  is (S_Idle, S_Nor, S_Judge, S_Hdr, S_Ldr, S_Chan1, S_Chan2, S_Chan3, S_Chan4, S_Chan5, S_Chan6, S_Chan7, S_Chan8);
    signal  fifo_state  : Fsm_Sd_Rx;
    -- sdram write state
    type    Fsm_Sd_Wr  is (S_Sd_Pre, S_Sd_Send, S_Sd_Ans);
    signal  ctrl_state  : Fsm_Sd_Wr;

    component SDRAM_RX_FIFO
    port(
        clk             : in  STD_LOGIC;
        rst             : in  STD_LOGIC;
        din             : in  STD_LOGIC_VECTOR(15 downto 0);
        wr_en           : in  STD_LOGIC;
        rd_en           : in  STD_LOGIC;
        dout            : out STD_LOGIC_VECTOR(15 downto 0);
        full            : out STD_LOGIC;
        empty           : out STD_LOGIC;
        prog_empty      : out STD_LOGIC);
    end component;

begin

    FIFO_Rst    <= not Rst_Sdr;
    Sd_Wr_Cs    <= Sd_Wr_Cs_r;

    C611 : SDRAM_RX_FIFO
    port map (
        clk             => Clk_Sdr,
        rst             => FIFO_Rst,
        din             => SDRX_FIFO_d,
        wr_en           => SDRX_FIFO_Wr,
        rd_en           => SDRX_FIFO_Req,
        dout            => Sd_Wr_Data,
        full            => open,
        empty           => SDRX_FIFO_Empty,
        prog_empty      => SDRX_FIFO_Prog_Empty);                               -- '1' when data <= 511

    ------------------------------------------------------------------------------
    -- handshake interaction with SDRAM in writing, data transmit from fifo to sdram
    ------------------------------------------------------------------------------
    process(Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            ctrl_state      <= S_Sd_Pre;
            sd_cnt          <= 0;
            Sd_Wr           <= '0';
            SDRX_FIFO_Req   <= '0';
            Sd_Wr_Cs_r      <= X"FE";                                           -- 1111 1110
            Sd_Wr_Addr      <= (others => '0');
            Addr_Ba         <= (others => '0');
            Addr_Row        <= (others => '0');
            Addr_Col        <= (others => '0');
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            case ctrl_state is
                when S_Sd_Pre =>
                    if (SDRX_FIFO_Prog_Empty = '0') then                        -- the data in SDRX_FIFO is > 511
                        ctrl_state  <= S_Sd_Send;
                        Sd_Wr       <= '1';
                        Sd_Wr_Addr  <= Addr_Ba & Addr_Row & Addr_Col;
                        if (Cs_Sign = '0') then
                            Sd_Wr_Cs_r  <= X"7F";                               -- 0111 1111
                        end if;
                    else
                        ctrl_state  <= S_Sd_Pre;
                    end if;

                when S_Sd_Send =>
                    if (Sd_Wr_Ack = '1') then
                        Sd_Wr       <= '0';
                        ctrl_state  <= S_Sd_Ans;
                    else
                        ctrl_state  <= S_Sd_Send;
                    end if;

                when S_Sd_Ans =>
                    if (sd_cnt = 1024) then                                     -- write 1024 16bit data at a time
                        if (Sd_Wr_End = '1') then                               -- sdram answer end sign
                            ctrl_state      <= S_Sd_Pre;
                            sd_cnt          <= 0;
                            if (CONV_INTEGER(Addr_Row) = 8191) then             -- col 1024, row 8192, ba 4
                                if (Cs_Sign = '0') then
                                    Addr_Ba     <= (others => '0');
                                    Sd_Wr_Cs_r  <= X"FE";
                                else
                                    if (Addr_Ba = "11") then
                                        Addr_Ba     <= (others => '0');
                                        if (Sd_Wr_Cs_r = X"BF") then            -- "10111111"  CS 7 (16*1024*8192*4*7=3.5G)
                                            Sd_Wr_Cs_r  <= X"FF";               -- "11111111"
                                        else
                                            Sd_Wr_Cs_r  <= Sd_Wr_Cs_r (6 downto 0) & '1';
                                        end if;
                                    else
                                        Addr_Ba     <= Addr_Ba + '1';
                                    end if;
                                end if;
                                Addr_Row    <= (others => '0');
                            else
                                Addr_Row    <= Addr_Row + '1';
                            end if;
                        else
                            ctrl_state      <= S_Sd_Ans;
                            sd_cnt          <= sd_cnt;
                        end if;
                        SDRX_FIFO_Req       <= '0';
                    else
                        ctrl_state          <= S_Sd_Ans;
                        sd_cnt              <= sd_cnt + 1;
                        SDRX_FIFO_Req       <= '1';
                    end if;

                when others =>
                    ctrl_state  <= S_Sd_Pre;
            end case;
        end if;
    end process;

    --*****************************************************
    -- synchronous signal
    ------------------------
    process(Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            Image_Out_r1        <= '0';
            Image_Out_r2        <= '0';
            Self_Image_Out_r1   <= '0';
            Self_Image_Out_r2   <= '0';
            Gain_Mode_r1        <= (others => '0');
            Gain_Mode_r2        <= (others => '0');
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            Image_Out_r1        <= Image_Out;
            Image_Out_r2        <= Image_Out_r1;
            Self_Image_Out_r1   <= Self_Image_Out;
            Self_Image_Out_r2   <= Self_Image_Out_r1;
            Gain_Mode_r1        <= Gain_Mode;
            Gain_Mode_r2        <= Gain_Mode_r1;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- merge 4 channel fifo data into one line data according to the Gain_Mode
    ------------------------------------------------------------------------------
    process(Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            fifo_state          <= S_Idle;
            data_cnt            <= 0;
            row_cnt             <= 0;
            Cs_Sign             <= '0';
            Nor_FIFO_Req        <= '0';
            RX_FIFO_Req_Chan1   <= '0';
            RX_FIFO_Req_Chan2   <= '0';
            RX_FIFO_Req_Chan3   <= '0';
            RX_FIFO_Req_Chan4   <= '0';
            RX_FIFO_Req_Chan5   <= '0';
            RX_FIFO_Req_Chan6   <= '0';
            RX_FIFO_Req_Chan7   <= '0';
            RX_FIFO_Req_Chan8   <= '0';
            SDRX_FIFO_Wr        <= '0';
            SDRX_FIFO_d         <= (others => '0');
            Store_Status        <= "00";
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            case fifo_state is
                when S_Idle =>
                    if (Nor_FIFO_Prog_Empty = '0' and SDRX_FIFO_Empty = '1') then    -- the data of the norflash fifo > 1024
                        fifo_state      <= S_Nor;
                        Nor_FIFO_Req    <= '1';
                        Cs_Sign         <= '0';
                        Store_Status    <= "10";                                -- store working
                    elsif (Image_Out_r2 = '1' or Self_Image_Out_r2 = '1') then
                        fifo_state      <= S_Judge;
                        Cs_Sign         <= '1';
                        Store_Status    <= "10";                                -- store working
                    else
                        fifo_state      <= S_Idle;
                    end if;
                    SDRX_FIFO_Wr    <= '0';
                --**********nor data*************
                 when S_Nor =>
                    if (data_cnt = 1023) then                                   -- one time 1024 data
                        fifo_state      <= S_Idle;
                        data_cnt        <= 0;
                        Nor_FIFO_Req    <= '0';
                        Store_Status    <= "01";                                -- store done
                    else
                        fifo_state      <= S_Nor;
                        data_cnt        <= data_cnt + 1;
                        Nor_FIFO_Req    <= '1';
                    end if;
                    SDRX_FIFO_d     <= Nor_FIFO_q;
                    SDRX_FIFO_Wr    <= '1';
                --**********cmos data*************
                when S_Judge =>
                    if (row_cnt = 2048) then
                        fifo_state      <= S_Idle;
                        row_cnt         <= 0;
                        Store_Status    <= "01";                                -- store done
                    else
                        if (Gain_Mode_r2 = X"11") then                          -- Gain_Mode HG
                            fifo_state  <= S_Hdr;
                        elsif (Gain_Mode_r2 = X"22") then                       -- Gain_Mode LG
                            fifo_state  <= S_Ldr;
                        else
                            fifo_state  <= S_Idle;
                        end if;
                    end if;
                    SDRX_FIFO_Wr    <= '0';

                 when S_Ldr =>
                    if (RX_FIFO_Prog_Chan1 = '0' and SDRX_FIFO_Empty = '1') then    -- the data of the fifo1 > 511
                        fifo_state          <= S_Chan1;
                        RX_FIFO_Req_Chan1   <= '1';
                    else
                        fifo_state          <= S_Ldr;
                    end if;

                 when S_Chan1 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Chan2;
                        data_cnt            <= 0;
                        RX_FIFO_Req_Chan1   <= '0';
                        RX_FIFO_Req_Chan2   <= '1';
                    else
                        fifo_state          <= S_Chan1;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan1   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan1;
                    SDRX_FIFO_Wr    <= '1';

                 when S_Chan2 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Chan3;
                        data_cnt            <= 0;
                        RX_FIFO_Req_Chan2   <= '0';
                        RX_FIFO_Req_Chan3   <= '1';
                    else
                        fifo_state          <= S_Chan2;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan2   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan2;
                    SDRX_FIFO_Wr    <= '1';

                 when S_Chan3 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Chan4;
                        data_cnt            <= 0;
                        RX_FIFO_Req_Chan3   <= '0';
                        RX_FIFO_Req_Chan4   <= '1';
                    else
                        fifo_state          <= S_Chan3;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan3   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan3;
                    SDRX_FIFO_Wr    <= '1';

                 when S_Chan4 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Judge;
                        data_cnt            <= 0;
                        row_cnt             <= row_cnt + 1;
                        RX_FIFO_Req_Chan4   <= '0';
                    else
                        fifo_state          <= S_Chan4;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan4   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan4;
                    SDRX_FIFO_Wr    <= '1';

                 when S_Hdr =>
                    if (RX_FIFO_Prog_Chan5 = '0' and SDRX_FIFO_Empty = '1') then    -- the data of the fifo5 > 511
                        fifo_state          <= S_Chan5;
                        RX_FIFO_Req_Chan5   <= '1';
                    else
                        fifo_state          <= S_Hdr;
                    end if;

                 when S_Chan5 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Chan6;
                        data_cnt            <= 0;
                        RX_FIFO_Req_Chan5   <= '0';
                        RX_FIFO_Req_Chan6   <= '1';
                    else
                        fifo_state          <= S_Chan5;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan5   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan5;
                    SDRX_FIFO_Wr    <= '1';

                 when S_Chan6 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Chan7;
                        data_cnt            <= 0;
                        RX_FIFO_Req_Chan6   <= '0';
                        RX_FIFO_Req_Chan7   <= '1';
                    else
                        fifo_state          <= S_Chan6;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan6   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan6;
                    SDRX_FIFO_Wr    <= '1';

                 when S_Chan7 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Chan8;
                        data_cnt            <= 0;
                        RX_FIFO_Req_Chan7   <= '0';
                        RX_FIFO_Req_Chan8   <= '1';
                    else
                        fifo_state          <= S_Chan7;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan7   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan7;
                    SDRX_FIFO_Wr    <= '1';

                 when S_Chan8 =>
                    if (data_cnt = 511) then                                    -- one channel 512 data
                        fifo_state          <= S_Judge;
                        data_cnt            <= 0;
                        row_cnt             <= row_cnt + 1;
                        RX_FIFO_Req_Chan8   <= '0';
                    else
                        fifo_state          <= S_Chan8;
                        data_cnt            <= data_cnt + 1;
                        RX_FIFO_Req_Chan8   <= '1';
                    end if;
                    SDRX_FIFO_d     <= RX_FIFO_q_Chan8;
                    SDRX_FIFO_Wr    <= '1';

                when others =>
                    fifo_state  <= S_Idle;
            end case;
        end if;
    end process;
end Behavioral;