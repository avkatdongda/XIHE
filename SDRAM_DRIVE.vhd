----------------------------------------------------------------------------------
-- Company: CIOMP
-- Engineer: WangZheng
-- Create Date:    16:11:19 01/08/2020 
-- Module Name:    SDRAM_DRIVE - Behavioral 
-- Project Name:   SEN_IMA
-- Target Devices: Virtex-4 xqr4vsx55-10cf1140
-- Tool versions:  ISE 14.2
-- Description:    sdram_drive drive the sdram for writing and reading (speed 7.5ns)
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

entity SDRAM_DRIVE is
    port (
        ---------CLOCKING---------
        Clk_Sdr                     : in  STD_LOGIC;                            -- sdram W/R clk 100MHz
        Rst_Sdr                     : in  STD_LOGIC;                            -- Clk_Sdr correspond rst signal
        ---------SDRAM_pin---------
        SD_DQ                       : inout STD_LOGIC_VECTOR (15 downto 0);     -- sdram data D0~D15
        SD_A                        : out STD_LOGIC_VECTOR (12 downto 0);       -- sdram addr A0~A12
        SD_BA                       : out STD_LOGIC_VECTOR (1 downto 0);        -- bank select addr
        SD_RAS                      : out STD_LOGIC;                            -- row addr strobe command, low level valid
        SD_CAS                      : out STD_LOGIC;                            -- col addr strobe command, low level valid
        SD_WE                       : out STD_LOGIC;                            -- write enable, low level valid
        SD_CKE                      : out STD_LOGIC;                            -- cke is valid to exit auto refresh and enter normal operation
        SD_CS                       : out STD_LOGIC_VECTOR (7 downto 0);        -- sdram chip selection 0~7, low level valid
        SD_UDQM                     : out STD_LOGIC;                            -- data input/output mask, up byte
        SD_LDQM                     : out STD_LOGIC;                            -- data input/output mask, low byte
        ---------SDRAM_RX---------
        Sd_Wr_Ack                   : out STD_LOGIC;                            -- the acknowledge signal after receiving Sd_Wr
        Sd_Wr_End                   : out STD_LOGIC;                            -- the end signal of writing data
        Sd_Wr                       : in  STD_LOGIC;                            -- the enable signal of starting writing
        Sd_Wr_Cs                    : in  STD_LOGIC_VECTOR (7 downto 0);        -- sdram chip select signal, write mode
        Sd_Wr_Addr                  : in  STD_LOGIC_VECTOR (24 downto 0);       -- BA(2)+ROW(A0~A12)+COL(A0~A9) address
        Sd_Wr_Data                  : in  STD_LOGIC_VECTOR (15 downto 0);       -- the data signal of writing
        ---------SDRAM_TX---------
        Sd_Rd_Ack                   : out STD_LOGIC;                            -- the acknowledge signal after receiving Sd_Rd
        Sd_Rd                       : in  STD_LOGIC;                            -- the enable signal of starting reading
        Sd_Rd_Cs                    : in  STD_LOGIC_VECTOR (7 downto 0);        -- sdram chip select signal, read mode
        Sd_Rd_Addr                  : in  STD_LOGIC_VECTOR (24 downto 0);       -- BA(2)+ROW(A0~A12)+COL(A0~A9) address
        Sd_Rd_Data                  : out STD_LOGIC_VECTOR (15 downto 0));      -- the data signal of reading
end SDRAM_DRIVE;

architecture Behavioral of SDRAM_DRIVE is

    -- con
    constant NOP                    : STD_LOGIC_VECTOR (2 downto 0) := "111";
    constant ACTIVE                 : STD_LOGIC_VECTOR (2 downto 0) := "011";
    constant READING                : STD_LOGIC_VECTOR (2 downto 0) := "101";
    constant WRITING                : STD_LOGIC_VECTOR (2 downto 0) := "100";
    constant BURST_TERMINATE        : STD_LOGIC_VECTOR (2 downto 0) := "110";
    constant PRECHARGE              : STD_LOGIC_VECTOR (2 downto 0) := "010";
    constant AUTO_REFRESH           : STD_LOGIC_VECTOR (2 downto 0) := "001";
    constant MODE_REGISTER_SET      : STD_LOGIC_VECTOR (2 downto 0) := "000";
    constant burstcount             : integer := 1024;
    -- reg
    signal  Wr_En                   : STD_LOGIC;
    signal  SD_CMD                  : STD_LOGIC_VECTOR (2 downto 0);            -- SD_RAS, SD_CAS, SD_WE
    signal  Power_Flag              : STD_LOGIC;
    signal  Refresh_Req             : STD_LOGIC;
    signal  Refresh_Ack             : STD_LOGIC;
    signal  Sd_Wr_Data_r            : STD_LOGIC_VECTOR (15 downto 0);
    -- cnt
    signal  dly_cnt                 : integer range 0 to 20000;                 -- delay count 200us
    signal  ref_cnt                 : integer range 0 to 1023;                  -- refresh count 6.5us
    signal  col_wcnt                : integer range 0 to 1023;                  -- count col in writing
    signal  col_rcnt                : integer range 0 to 1023;                  -- count col in reading
    signal  clk_cnt                 : integer range 0 to 20;                    -- count clk in state
    signal  pre_cnt                 : integer range 0 to 8;                     -- count pre times in state

    -- fsm
    type    Fsm_Sdram is (I_Nop, I_Pre, I_Wait_Pre, I_Aref, I_Wait_Aref, I_Mrs, I_Wait_Mrs, I_Rdy,
                          S_Idle, S_Nop, S_Wr, S_Wr_Act, S_Wr_S, S_Wrb, S_Wbt, S_Wait_Wbt, S_Pre, S_Wait_Pre,
                          S_Aref, S_Wait_Aref, S_Rd, S_Rd_Act, S_Rd_S, S_Rdb, S_Rbt, S_Wait_Rbt);
    signal  state   : Fsm_Sdram;

    attribute IOB   : string;
    attribute IOB of Sd_Rd_Data     : signal is "TRUE";
    attribute IOB of Sd_Wr_Data_r   : signal is "TRUE";

begin
    SD_UDQM     <= '0';
    SD_LDQM     <= '0';
    SD_RAS      <= SD_CMD(2);
    SD_CAS      <= SD_CMD(1);
    SD_WE       <= SD_CMD(0);

    --**********************3 STATE SD_DATA**********************
    process(Clk_Sdr) begin
        if (Clk_Sdr'event and Clk_Sdr = '1') then
            Sd_Rd_Data      <= SD_DQ;
            Sd_Wr_Data_r    <= Sd_Wr_Data;
        end if;
    end process;
    SD_DQ   <= Sd_Wr_Data_r when (Wr_En = '1') else (others => 'Z');

    --*****************************************************
    -- delay 200us to generate the flag for SDRAM power up
    ------------------------
    process (Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            dly_cnt     <= 0;
            Power_Flag  <= '0';
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            if (dly_cnt = 20000) then
                Power_Flag  <= '1';
            else
                dly_cnt     <= dly_cnt + 1;
            end if;
        end if;
    end process;

    --*****************************************************
    -- at least 7.81us refresh once, 64ms need refresh 8192 times
    ------------------------
    process (Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            ref_cnt     <= 0;
            Refresh_Req <= '0';
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            if (ref_cnt = 650) then                                             -- 6.5us
                if (Refresh_Ack = '1') then
                    ref_cnt     <= 0;
                else
                    Refresh_Req <= '1';
                end if;
            else
                Refresh_Req <= '0';
                ref_cnt     <= ref_cnt + 1;
            end if;
        end if;
    end process;

    process (Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            state       <= I_Nop;
            clk_cnt     <= 0;
            pre_cnt     <= 0;
            col_wcnt    <= 0;
            col_rcnt    <= 0;
            SD_CKE      <= '1';
            Sd_Rd_Ack   <= '0';
            Sd_Wr_Ack   <= '0';
            Sd_Wr_End   <= '0';
            Wr_En       <= '0';
            Refresh_Ack <= '0';
            SD_CMD      <= NOP;
            SD_BA       <= "00";
            SD_A        <= (others => '0');
            SD_CS       <= (others => '0');
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            case state is
                --*****************************************************
                -- sdram initial state machine
                ------------------------
                when I_Nop =>
                    if (Power_Flag = '1') then                                  -- wait for 200us
                        state   <= I_Pre;
                    else
                        state   <= I_Nop;
                        SD_CMD  <= NOP;
                    end if;

                when I_Pre =>
                    state   <= I_Wait_Pre;
                    SD_CMD  <= PRECHARGE;
                    SD_BA   <= "00";
                    SD_A    <= "0010000000000";                                 -- precharge.all the bank, A10 high level

                when I_Wait_Pre =>
                    SD_CMD  <= NOP;
                    if (clk_cnt = 2) then                                       -- tRP(PRE to ACT), precharge wait 3 clk, min 15ns
                        state   <= I_Aref;
                        clk_cnt <= 0;
                    else
                        state   <= I_Wait_Pre;
                        clk_cnt <= clk_cnt + 1;
                    end if;

                when I_Aref =>
                    state   <= I_Wait_Aref;
                    SD_CMD  <= AUTO_REFRESH;
                    SD_BA   <= "00";
                    SD_A    <= "0010000000000";

                when I_Wait_Aref =>
                    SD_CMD  <= NOP;
                    if (clk_cnt = 9) then                                       -- tRC(REF to ACT), once auto refresh wait 10 clk, min 60ns
                        clk_cnt     <= 0;
                        if (pre_cnt = 7) then                                   -- auto refresh 8 times
                            state   <= I_Mrs;
                            pre_cnt <= 0;
                        else
                            state   <= I_Aref;
                            pre_cnt <= pre_cnt + 1;
                        end if;
                    else
                        clk_cnt     <= clk_cnt + 1;
                        state       <= I_Wait_Aref;
                    end if;

                when I_Mrs =>
                    state   <= I_Wait_Mrs;
                    SD_CMD  <= MODE_REGISTER_SET;
                    SD_BA   <= "00";
                    SD_A    <= "0000000110111";                                 -- BR length: 111, full page. BR type: 0, sequential.
                                                                                -- CAS latency: 011, 3. Operating mode: 00, standard.
                when I_Wait_Mrs =>
                    SD_CMD  <= NOP;
                    if (clk_cnt = 1) then                                      -- tMRD(MRS to ready), mode register program wait 2 clk, min 15ns
                        state   <= I_Rdy;
                        clk_cnt <= 0;
                    else
                        state   <= I_Wait_Mrs;
                        clk_cnt <= clk_cnt + 1;
                    end if;

                when I_Rdy =>
                    state   <= S_Idle;
                    SD_CMD  <= NOP;
                --*****************************************************
                -- sdram run state machine
                ------------------------
                when S_Idle =>
                    state   <= S_Nop;
                    SD_CMD  <= NOP;
                    SD_CKE  <= '1';

                when S_Nop =>
                    ---------refresh request---------
                    if (Refresh_Req = '1') then
                        state       <= S_Pre;
                        Refresh_Ack <= '1';
                        SD_CS       <= (others => '0');
                    ---------write request---------
                    elsif (Sd_Wr = '1') then
                        state       <= S_Wr;
                        Sd_Wr_Ack   <= '0';
                        Sd_Wr_End   <= '0';
                        SD_CS       <= Sd_Wr_Cs;                                -- select CS
                        SD_BA       <= Sd_Wr_Addr(24 downto 23);                -- select BA
                        SD_A        <= Sd_Wr_Addr(22 downto 10);                -- select ROW
                    ---------read request---------
                    elsif (Sd_Rd = '1') then
                        state       <= S_Rd;
                        Sd_Rd_Ack   <= '0';
                        SD_CS       <= Sd_Rd_Cs;                                -- select CS
                        SD_BA       <= Sd_Rd_Addr(24 downto 23);                -- select BA
                        SD_A        <= Sd_Rd_Addr(22 downto 10);                -- select ROW
                    else
                        state       <= S_Nop;
                        SD_CMD      <= NOP;
                    end if;
                    SD_CKE  <= '1';

                --*****************************************************
                -- write response
                when S_Wr =>                                                    -- active
                    state   <= S_Wr_Act;
                    Wr_En   <= '1';
                    SD_CMD  <= ACTIVE;

                when S_Wr_Act =>
                    SD_CMD  <= NOP;
                    SD_A(9 downto 0)    <= Sd_Wr_Addr(9 downto 0);              -- select column: A0-A9
                    if (clk_cnt = 2) then                                       -- tRCD(ACT to R/W), delay wait 3 clk, min 15ns
                        state       <= S_Wr_S;
                        clk_cnt     <= 0;
                        Sd_Wr_Ack   <= '0';                                     -- pull Sd_Wr_Ack high 2 clk
                    else
                        state       <= S_Wr_Act;
                        clk_cnt     <= clk_cnt + 1;
                        Sd_Wr_Ack   <= '1';
                    end if;

                when S_Wr_S =>
                    state   <= S_Wrb;
                    SD_CMD  <= WRITING;                                         -- write command

                when S_Wrb =>
                    if (col_wcnt = burstcount - 1) then                         -- 1023
                        state       <= S_Wbt;
                        col_wcnt    <= 0;
                        SD_CMD      <= BURST_TERMINATE;                         -- burst stop when write done full page
                        Wr_En       <= '0';
                    else
                        state       <= S_Wrb;
                        col_wcnt    <= col_wcnt + 1;
                        SD_CMD      <= NOP;
                        Wr_En       <= '1';
                    end if;

                when S_Wbt =>
                    state   <= S_Wait_Wbt;
                    SD_CMD  <= PRECHARGE;                                       -- change next row
                    SD_BA   <= "00";
                    SD_A    <= "0010000000000";

                when S_Wait_Wbt =>
                    SD_CMD  <= NOP;
                    if (clk_cnt = 2) then                                      -- tRP(PRE to ACT), precharge wait 3 clk, min 15ns
                        state       <= S_Nop;
                        clk_cnt     <= 0;
                        Sd_Wr_End   <= '1';                                     -- Sd_Wr_End pull high 1 clk
                    else
                        state       <= S_Wait_Wbt;
                        clk_cnt     <= clk_cnt + 1;
                    end if;

                --*****************************************************
                -- read response
                when S_Rd =>                                                    -- active
                    state       <= S_Rd_Act;
                    SD_CMD      <= ACTIVE;
                    Sd_Rd_Ack   <= '0';

                when S_Rd_Act =>
                    SD_CMD      <= NOP;
                    SD_A(9 downto 0)    <= Sd_Rd_Addr(9 downto 0);              -- select column: A0-A9
                    if (clk_cnt = 2) then                                       -- tRCD(ACT to R/W), delay wait 3 clk, min 15ns
                        state   <= S_Rd_S;
                        clk_cnt <= 0;
                        SD_CMD  <= READING;                                     -- read command
                    else
                        state   <= S_Rd_Act;
                        clk_cnt <= clk_cnt + 1;
                    end if;

                when S_Rd_S =>
                    if (clk_cnt = 2) then                                       -- read delay 3 clk, CAS latency - 3
                        state       <= S_Rdb;
                        clk_cnt     <= 0;
                        Sd_Rd_Ack   <= '1';                                     -- pull Sd_Rd_Ack high 1 clk
                    else
                        state       <= S_Rd_S;
                        clk_cnt     <= clk_cnt + 1;
                        SD_CMD      <= NOP;
                    end if;

                when S_Rdb =>
                    if (col_rcnt = burstcount - 4) then                         -- 1020, x = 2 cycles
                        state       <= S_Rdb;
                        col_rcnt    <= col_rcnt + 1;
                        SD_CMD      <= BURST_TERMINATE;
                    elsif (col_rcnt = burstcount - 1) then                      -- 1023
                        state       <= S_Rbt;
                        col_rcnt    <= 0;
                        SD_CMD      <= NOP;
                    else
                        state       <= S_Rdb;
                        col_rcnt    <= col_rcnt + 1;                            -- col_rcnt = 1 is the first SD_DQ
                        SD_CMD      <= NOP;
                    end if;
                    Sd_Rd_Ack   <= '0';

                when S_Rbt =>
                    state       <= S_Wait_Rbt;
                    SD_CMD      <= PRECHARGE;                                   -- change next row
                    SD_BA       <= "00";
                    SD_A        <= "0010000000000";

                when S_Wait_Rbt =>
                    SD_CMD      <= NOP;
                    if (clk_cnt = 2) then                                       -- tRP(PRE to ACT), precharge wait 3 clk, min 15ns
                        state   <= S_Nop;
                        clk_cnt <= 0;
                    else
                        state   <= S_Wait_Rbt;
                        clk_cnt <= clk_cnt + 1;
                    end if;

                --*****************************************************
                -- refresh response
                when S_Pre =>
                    state       <= S_Wait_Pre;
                    SD_CMD      <= PRECHARGE;
                    SD_BA       <= "00";
                    SD_A        <= "0010000000000";                             -- precharge.all the bank, A10 high level

                when S_Wait_Pre =>
                    SD_CMD      <= NOP;
                    Refresh_Ack <= '0';
                    if (clk_cnt = 2) then                                       -- tRP(PRE to ACT), precharge wait 3 clk, min 15ns
                        state   <= S_Aref;
                        clk_cnt <= 0;
                    else
                        state   <= S_Wait_Pre;
                        clk_cnt <= clk_cnt + 1;
                    end if;

               when S_Aref =>
                    state       <= S_Wait_Aref;
                    SD_CMD      <= AUTO_REFRESH;
                    SD_BA       <= "00";     
                    SD_A        <= "0010000000000";

                when S_Wait_Aref =>
                    SD_CMD      <= NOP;
                    if (clk_cnt = 9) then                                       -- tRC(REF to ACT), once auto refresh wait 10 clk, min 60ns
                        clk_cnt <= 0;
                        if (pre_cnt = 1) then                                   -- auto refresh 2 times
                            state   <= S_Nop;
                            pre_cnt <= 0;
                        else
                            state   <= S_Aref;
                            pre_cnt <= pre_cnt + 1;
                        end if;
                    else
                        state   <= S_Wait_Aref;
                        clk_cnt <= clk_cnt + 1;
                    end if;

                when others =>
                    state       <= S_Idle;
                    clk_cnt     <= 0;
                    pre_cnt     <= 0;
                    col_wcnt    <= 0;
                    col_rcnt    <= 0;
                    Sd_Rd_Ack   <= 'X';
                    Sd_Wr_Ack   <= 'X';
                    Sd_Wr_End   <= 'X';
                    Wr_En       <= 'X';
                    Refresh_Ack <= 'X';
                    SD_CMD      <= (others => 'X');
                    SD_BA       <= (others => 'X');
                    SD_A        <= (others => 'X');
            end case;
        end if;
    end process;
end Behavioral;