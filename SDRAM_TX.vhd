----------------------------------------------------------------------------------
-- Company:         CIOMP
-- Engineer:        WangZheng
-- Create Date:     15:21:31 01/16/2020
-- Module Name:     SDRAM_TX - Behavioral
-- Project Name:    SEN_IMA
-- Target Devices:  Virtex-4 xqr4vsx55-10cf1140
-- Tool versions:   ISE 14.7
-- Description:     sdram_tx transmit the sdram image data to a tx fifo
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

entity SDRAM_TX is
    generic (
        Cms_Class                   : STD_LOGIC_VECTOR (7 downto 0):= X"AA";    -- set class CMOSA AA, CMOSB 55
        Cms_Head                    : STD_LOGIC_VECTOR (7 downto 0):= X"EA");   -- set head CMOSA EA, CMOSB EB
    port (
        ---------CLOCKING---------
        Clk_Sdr                     : in  STD_LOGIC;                            -- sdram W/R clk 100MHz
        Rst_Sdr                     : in  STD_LOGIC;                            -- Clk_Sdr correspond rst signal
        Clk_Sys                     : in  STD_LOGIC;                            -- system clk 80MHz
        Rst_Sys                     : in  STD_LOGIC;                            -- Clk_Sys correspond rst signal
        ---------SERIAL_CMD---------
        Sign_Data                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- Sign_Data BBH(set) CCH(ctrl) DDH(inquire)
        Commond_Data                : in  STD_LOGIC_VECTOR (7 downto 0);        -- Commond_Data 11H 22H 44H 55H 88H AAH BBH correspond different Sign_Data
        Frame_Num                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- Frame_Num 01H~14H, default 01H.
        Exposure_Line               : in  STD_LOGIC_VECTOR (15 downto 0);       -- Exposure_Line 0000H~FFFFH default 0100H
        Gain_Mode                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- sensor Gain_Mode HG/LG 11H/22H, default 00H
        Sen_Class                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- down CMOSA or CMOSB, CMOSA AA, CMOSB 55
        Time_Code                   : in  STD_LOGIC_VECTOR (47 downto 0);       -- system time code, 0~FFFFFFH
        Down_Frame                  : in  STD_LOGIC_VECTOR (7 downto 0);        -- the frame numble of down
        Corr_Mode                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- down correction mode, on 0xAA, off 0x55
        Corr_Status                 : out STD_LOGIC_VECTOR (1 downto 0);        -- the status of nonuniform correction, "10" is working, "01" none
        ---------SEN_DRIVE---------
        Image_Out                   : in  STD_LOGIC;                            -- pull high when the image's output is valid
        ---------SEN_SPI---------
        Sen_Temp_Aux                : in  STD_LOGIC_VECTOR (15 downto 0);       -- the temperature of sensor in auxiliary packet
        Spi_Gaintop_Aux             : in  STD_LOGIC_VECTOR (7 downto 0);        -- read spi low gain register in auxiliary packet
        Spi_Gainbot_Aux             : in  STD_LOGIC_VECTOR (7 downto 0);        -- read spi high gain register in auxiliary packet
        ---------SEN_CTRL---------
        Start_Tx_Flag               : in  STD_LOGIC;                            -- the command of send instruction
        ---------SDRAM_DRIVE---------
        Sd_Rd_Ack                   : in  STD_LOGIC;                            -- the acknowledge signal after receiving Sd_Rd
        Sd_Rd                       : out STD_LOGIC;                            -- the enable signal of starting reading
        Sd_Rd_Cs                    : out STD_LOGIC_VECTOR (7 downto 0);        -- sdram chip select signal, read mode
        Sd_Rd_Addr                  : out STD_LOGIC_VECTOR (24 downto 0);       -- BA(2)+ROW(A0~A12)+COL(A0~A9) address
        Sd_Rd_Data                  : in  STD_LOGIC_VECTOR (15 downto 0);       -- the data signal of reading
        ---------IMA_TX---------
        Encode_Empty                : in  STD_LOGIC;                            -- '1' when encode fifo is empty
        Encode_En                   : out STD_LOGIC;                            -- Encode_Data_in enable
        Encode_Data_in              : out STD_LOGIC_VECTOR (7 downto 0));       -- encode fifo data signal input
end SDRAM_TX;

architecture Behavioral of SDRAM_TX is

    -- reg
    signal  Sign_Data_r             : STD_LOGIC_VECTOR (7 downto 0);
    signal  Commond_Data_r          : STD_LOGIC_VECTOR (7 downto 0);
    signal  Sen_Class_r             : STD_LOGIC_VECTOR (7 downto 0);
    signal  Down_Frame_r            : STD_LOGIC_VECTOR (7 downto 0);
    signal  Corr_Mode_r             : STD_LOGIC_VECTOR (7 downto 0);
    signal  Sen_Temp_Aux_r          : STD_LOGIC_VECTOR (15 downto 0);
    signal  Spi_Gaintop_Aux_r       : STD_LOGIC_VECTOR (7 downto 0);
    signal  Spi_Gainbot_Aux_r       : STD_LOGIC_VECTOR (7 downto 0);
    signal  Start_Tx_Flag_r1        : STD_LOGIC;
    signal  Start_Tx_Flag_r2        : STD_LOGIC;
    signal  Start_Tx_Flag_r3        : STD_LOGIC;
    signal  Start_Tx_Flag_r4        : STD_LOGIC;
    signal  Encode_Empty_r1         : STD_LOGIC;
    signal  Encode_Empty_r2         : STD_LOGIC;
    signal  Image_Out_r1            : STD_LOGIC;
    signal  Image_Out_r2            : STD_LOGIC;
    signal  Image_Out_r3            : STD_LOGIC;
    signal  Out_Lock                : STD_LOGIC;
    signal  Rd_Kb_En                : STD_LOGIC;                                -- '0' is reading data, '1' is reading k b
    signal  Addr_Ba                 : STD_LOGIC_VECTOR (1 downto 0);            -- sdram read ba addr
    signal  Addr_Ba_r               : STD_LOGIC_VECTOR (1 downto 0);            -- sdram read ba addr register
    signal  Addr_Row                : STD_LOGIC_VECTOR (12 downto 0);           -- sdram read row addr
    signal  Addr_Row_Start          : STD_LOGIC_VECTOR (12 downto 0);           -- sdram read start row addr
    signal  Addr_Row_End            : STD_LOGIC_VECTOR (12 downto 0);           -- sdram read end row addr
    signal  Addr_Row_K              : STD_LOGIC_VECTOR (12 downto 0);           -- sdram read k start addr
    signal  Addr_Row_B              : STD_LOGIC_VECTOR (12 downto 0);           -- sdram read b start addr
    signal  Addr_Col                : STD_LOGIC_VECTOR (9 downto 0);            -- sdram read end col addr
    signal  Line_Num                : STD_LOGIC_VECTOR (15 downto 0);           -- count output the line number
    signal  Exp_Time_Code           : STD_LOGIC_VECTOR (47 downto 0);           -- exposure time
    -- SDRAM_TX_FIFO
    signal  FIFO_Rst                : STD_LOGIC;
    signal  SDTX_FIFO_d             : STD_LOGIC_VECTOR (15 downto 0);           -- input
    signal  SDTX_FIFO_q             : STD_LOGIC_VECTOR (7 downto 0);            -- output
    signal  SDTX_FIFO_Wr            : STD_LOGIC;
    signal  SDTX_FIFO_Full          : STD_LOGIC;
    signal  SDTX_FIFO_Empty         : STD_LOGIC;
    signal  SDTX_FIFO_Req           : STD_LOGIC;
    signal  SDTX_FIFO_Prog          : STD_LOGIC;
    signal  SDTX_FIFO_Prog_r1       : STD_LOGIC;
    signal  SDTX_FIFO_Prog_r2       : STD_LOGIC;
    -- SDRAM_KB_RAM
    signal  SDK_RAM_Wr              : STD_LOGIC_VECTOR (0 downto 0);
    signal  SDK_RAM_Addra           : STD_LOGIC_VECTOR (9 downto 0);
    signal  SDK_RAM_d               : STD_LOGIC_VECTOR (15 downto 0);
    signal  SDK_RAM_Addrb           : STD_LOGIC_VECTOR (9 downto 0);
    signal  SDK_RAM_q               : STD_LOGIC_VECTOR (15 downto 0);
    signal  SDB_RAM_Wr              : STD_LOGIC_VECTOR (0 downto 0);
    signal  SDB_RAM_Addra           : STD_LOGIC_VECTOR (9 downto 0);
    signal  SDB_RAM_d               : STD_LOGIC_VECTOR (15 downto 0);
    signal  SDB_RAM_Addrb           : STD_LOGIC_VECTOR (9 downto 0);
    signal  SDB_RAM_q               : STD_LOGIC_VECTOR (15 downto 0);
    -- MUL_ADD
    signal  Mul_Add_A               : STD_LOGIC_VECTOR (15 downto 0);           -- the data signal
    signal  Mul_Add_B               : STD_LOGIC_VECTOR (15 downto 0);           -- the k signal of
    signal  Mul_Add_C               : STD_LOGIC_VECTOR (15 downto 0);           -- the b signal of
    signal  Mul_Add_O               : STD_LOGIC_VECTOR (15 downto 0);           -- the result signal 16bit
    signal  Mul_Add_P               : STD_LOGIC_VECTOR (47 downto 0);           -- the result signal 48bit
    -- cnt
    signal  data_cnt                : integer range 0 to 4095;                  -- count 8bit data into encode fifo, 4100 byte
    signal  sd_cnt                  : integer range 0 to 1100;                  -- count 16bit data out from sdram
    signal  aux_cnt                 : integer range 0 to 30;                    -- count auxiliary packet
    -- fsm
    -- sdram tx fifo state
    type    Fsm_Sd_Tx  is (S_Idle, S_Pre, S_Head1, S_Head2, S_Line1, S_Line2, S_Data, S_Judge, S_Aux_Pre, S_Aux, S_Aux_D);
    signal  fifo_state  : Fsm_Sd_Tx;
    -- sdram read state
    type    Fsm_Sd_Rd  is (S_Sd_Idle, S_Sd_Value, S_Sd_Pre_Off, S_Sd_Send_Off, S_Sd_Ans_Off, S_Sd_K_Pre_On, S_Sd_K_Send_On, S_Sd_K_Ans_On,
                           S_Sd_B_Pre_On, S_Sd_B_Send_On, S_Sd_B_Ans_On, S_Sd_Pre_On, S_Sd_Send_On, S_Sd_Ans_On);
    signal  ctrl_state  : Fsm_Sd_Rd;

    component SDRAM_TX_FIFO
    port(
        rst             : in  STD_LOGIC;
        wr_clk          : in  STD_LOGIC;
        rd_clk          : in  STD_LOGIC;
        din             : in  STD_LOGIC_VECTOR(15 downto 0);
        wr_en           : in  STD_LOGIC;
        rd_en           : in  STD_LOGIC;
        dout            : out STD_LOGIC_VECTOR(7 downto 0);
        full            : out STD_LOGIC;
        empty           : out STD_LOGIC;
        prog_empty      : out STD_LOGIC);
    end component;

    component SDRAM_KB_RAM
    port (
        clka            : in  STD_LOGIC;                                        -- clk 100MHz
        wea             : in  STD_LOGIC_VECTOR (0 downto 0);                    -- write enable
        addra           : in  STD_LOGIC_VECTOR (9 downto 0);                    -- addr 0~1023
        dina            : in  STD_LOGIC_VECTOR (15 downto 0);                   -- input data
        clkb            : in  STD_LOGIC;                                        -- clk 100MHz
        addrb           : in  STD_LOGIC_VECTOR (9 downto 0);                    -- addr 0~1023
        doutb           : out STD_LOGIC_VECTOR (15 downto 0));                  -- output data
    end component;

    component MUL_ADD
    port(
        clk             : in  STD_LOGIC;
        ce              : in  STD_LOGIC;
        sclr            : in  STD_LOGIC;
        a               : in  STD_LOGIC_VECTOR(15 downto 0);
        b               : in  STD_LOGIC_VECTOR(15 downto 0);
        c               : in  STD_LOGIC_VECTOR(15 downto 0);
        subtract        : in  STD_LOGIC;
        p               : out STD_LOGIC_VECTOR(21 downto 6);
        pcout           : out STD_LOGIC_VECTOR(47 downto 0));
    end component;

begin

    FIFO_Rst    <= not Rst_Sdr;

    C631 : SDRAM_TX_FIFO
    port map (
        rst             => FIFO_Rst,
        wr_clk          => Clk_Sdr,
        rd_clk          => Clk_Sys,
        din             => SDTX_FIFO_d,
        wr_en           => SDTX_FIFO_Wr,
        rd_en           => SDTX_FIFO_Req,
        dout            => SDTX_FIFO_q,
        full            => SDTX_FIFO_Full,
        empty           => SDTX_FIFO_Empty,
        prog_empty      => SDTX_FIFO_Prog);                                     -- '1' when data <= 2047


    U632 : SDRAM_KB_RAM
    port map (
        clka            => Clk_Sdr,
        wea             => SDK_RAM_Wr,
        addra           => SDK_RAM_Addra,
        dina            => SDK_RAM_d,
        clkb            => Clk_Sdr,
        addrb           => SDK_RAM_Addrb,
        doutb           => SDK_RAM_q);

    U633 : SDRAM_KB_RAM
    port map (
        clka            => Clk_Sdr,
        wea             => SDB_RAM_Wr,
        addra           => SDB_RAM_Addra,
        dina            => SDB_RAM_d,
        clkb            => Clk_Sdr,
        addrb           => SDB_RAM_Addrb,
        doutb           => SDB_RAM_q);

    U634 : MUL_ADD
    port map (
        clk             => Clk_Sdr,
        ce              => '1',
        sclr            => '0',
        a               => Mul_Add_A,       --data
        b               => Mul_Add_B,       --k
        c               => Mul_Add_C,       --b
        subtract        => '0',             --'1' subtract, '0' add
        p               => Mul_Add_O,
        pcout           => Mul_Add_P);

    --*****************************************************
    -- synchronous signal
    ------------------------
    process(Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            SDTX_FIFO_Prog_r1   <= '1';
            SDTX_FIFO_Prog_r2   <= '1';
            Start_Tx_Flag_r1    <= '0';
            Start_Tx_Flag_r2    <= '0';
            Sign_Data_r         <= (others => '0');
            Commond_Data_r      <= (others => '0');
            Sen_Class_r         <= (others => '0');
            Down_Frame_r        <= (others => '0');
            Corr_Mode_r         <= (others => '0');
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            SDTX_FIFO_Prog_r1   <= SDTX_FIFO_Prog;
            SDTX_FIFO_Prog_r2   <= SDTX_FIFO_Prog_r1;
            Start_Tx_Flag_r1    <= Start_Tx_Flag;
            Start_Tx_Flag_r2    <= Start_Tx_Flag_r1;
            Sign_Data_r         <= Sign_Data;
            Commond_Data_r      <= Commond_Data;
            Sen_Class_r         <= Sen_Class;
            Down_Frame_r        <= Down_Frame;
            Corr_Mode_r         <= Corr_Mode;
        end if;
    end process;

    --*****************************************************
    -- synchronous 20M and 40M signal
    ------------------------
    process(Clk_Sys, Rst_Sys) begin
        if (Rst_Sys = '0') then
            Image_Out_r1        <= '0';
            Image_Out_r2        <= '0';
            Image_Out_r3        <= '0';
            Encode_Empty_r1     <= '1';
            Encode_Empty_r2     <= '1';
            Start_Tx_Flag_r3    <= '0';
            Start_Tx_Flag_r4    <= '0';
            Sen_Temp_Aux_r      <= (others => '0');
            Spi_Gaintop_Aux_r   <= (others => '0');
            Spi_Gainbot_Aux_r   <= (others => '0');
        elsif (Clk_Sys'event and Clk_Sys = '1') then
            Image_Out_r1        <= Image_Out;
            Image_Out_r2        <= Image_Out_r1;
            Image_Out_r3        <= Image_Out_r2;
            Encode_Empty_r1     <= Encode_Empty;
            Encode_Empty_r2     <= Encode_Empty_r1;
            Start_Tx_Flag_r3    <= Start_Tx_Flag;
            Start_Tx_Flag_r4    <= Start_Tx_Flag_r3;
            Sen_Temp_Aux_r      <= Sen_Temp_Aux;
            Spi_Gaintop_Aux_r   <= Spi_Gaintop_Aux;
            Spi_Gainbot_Aux_r   <= Spi_Gainbot_Aux;
        end if;
    end process;

    --*****************************************************
    -- lock exposure time code
    ------------------------
    process(Clk_Sys, Rst_Sys) begin
        if (Rst_Sys = '0') then
            Out_Lock        <= '0';
            Exp_Time_Code   <= (others => '0');
        elsif (Clk_Sys'event and Clk_Sys = '1') then
            if (Out_Lock = '0') then
                if (Image_Out_r3 = '0' and Image_Out_r2 = '1') then     -- rising Image_Out
                    Exp_Time_Code   <= Time_Code;
                    Out_Lock        <= '1';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- set CS, Addr_Ba, Addr_Row start and end
    ------------------------------------------------------------------------------
    process(Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            Sd_Rd_Cs        <= (others => '1');
            Addr_Ba_r       <= (others => '0');
            Addr_Row_Start  <= (others => '0');
            Addr_Row_End    <= (others => '0');
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            if (Rd_Kb_En = '0') then
                case CONV_INTEGER(Down_Frame_r) is
                    when 0 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "00";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 1 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "00";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 2 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "01";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 3 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "01";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 4 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "10";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 5 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "10";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 6 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "11";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 7 =>
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "11";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 8 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "00";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 9 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "00";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 10 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "01";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 11 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "01";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 12 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "10";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 13 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "10";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 14 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "11";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 15 =>
                        Sd_Rd_Cs        <= X"FD";
                        Addr_Ba_r       <= "11";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 16 =>
                        Sd_Rd_Cs        <= X"FB";
                        Addr_Ba_r       <= "00";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 17 =>
                        Sd_Rd_Cs        <= X"FB";
                        Addr_Ba_r       <= "00";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 18 =>
                        Sd_Rd_Cs        <= X"FB";
                        Addr_Ba_r       <= "01";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when 19 =>
                        Sd_Rd_Cs        <= X"FB";
                        Addr_Ba_r       <= "01";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                    when 20 =>
                        Sd_Rd_Cs        <= X"FB";
                        Addr_Ba_r       <= "10";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(0, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(4095, 13);
                    when others =>      --1
                        Sd_Rd_Cs        <= X"FE";
                        Addr_Ba_r       <= "00";
                        Addr_Row_Start  <= CONV_STD_LOGIC_VECTOR(4096, 13);
                        Addr_Row_End    <= CONV_STD_LOGIC_VECTOR(8191, 13);
                end case;
            else
                Sd_Rd_Cs    <= X"7F";
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- handshake interaction with SDRAM in reading
    ------------------------------------------------------------------------------
    process(Clk_Sdr, Rst_Sdr) begin
        if (Rst_Sdr = '0') then
            ctrl_state      <= S_Sd_Idle;
            sd_cnt          <= 0;
            Sd_Rd           <= '0';
            Rd_Kb_En        <= '0';
            SDTX_FIFO_Wr    <= '0';
            SDTX_FIFO_d     <= (others => '0');
            Sd_Rd_Addr      <= (others => '0');
            Addr_Ba         <= (others => '0');
            Addr_Row        <= (others => '0');
            Addr_Row_K      <= (others => '0');
            Addr_Row_B      <= (others => '0');
            Addr_Col        <= (others => '0');
            SDK_RAM_Wr      <= "0";
            SDK_RAM_d       <= (others => '0');
            SDK_RAM_Addra   <= (others => '0');
            SDK_RAM_Addrb   <= (others => '0');
            SDB_RAM_Wr      <= "0";
            SDB_RAM_d       <= (others => '0');
            SDB_RAM_Addra   <= (others => '0');
            SDB_RAM_Addrb   <= (others => '0');
            Mul_Add_A       <= (others => '0');
            Mul_Add_B       <= (others => '0');
            Mul_Add_C       <= (others => '0');
            Corr_Status     <= "00";
        elsif (Clk_Sdr'event and Clk_Sdr = '1') then
            case ctrl_state is
                --**************judge correction mode*****************
                when S_Sd_Idle =>
                    if (Sign_Data_r = X"CC" and Commond_Data_r = X"BB" and Sen_Class_r = Cms_Class and Corr_Mode_r = X"55" and Start_Tx_Flag_r2 = '1') then       -- down 2k*2k corr off
                        ctrl_state  <= S_Sd_Value;
                        Rd_Kb_En    <= '0';
                        Corr_Status <= "00";                                    -- none
                    elsif (Sign_Data_r = X"CC" and Commond_Data_r = X"BB" and Sen_Class_r = Cms_Class and Corr_Mode_r = X"AA" and Start_Tx_Flag_r2 = '1') then    -- down 2k*2k corr on
                        ctrl_state  <= S_Sd_Value;
                        Rd_Kb_En    <= '1';
                        Corr_Status <= "10";                                    -- nonuniform working
                    else
                        ctrl_state  <= S_Sd_Idle;
                    end if;
                    Sd_Rd       <= '0';
                --**************set value to row and ba*****************
                when S_Sd_Value =>
                    if (Rd_Kb_En = '0') then
                        ctrl_state  <= S_Sd_Pre_Off;
                        Addr_Row    <= Addr_Row_Start;
                        Addr_Ba     <= Addr_Ba_r;
                    else
                        ctrl_state  <= S_Sd_K_Pre_On;
                        Addr_Row    <= Addr_Row_Start;                          -- set data row value
                        Addr_Row_K  <= CONV_STD_LOGIC_VECTOR(0, 13);            -- start at 0
                        Addr_Row_B  <= CONV_STD_LOGIC_VECTOR(4096, 13);         -- start at 4096
                        Addr_Ba     <= "00";
                    end if;
                --**************take data from sdram to fifo without correction loop 4096*****************
                when S_Sd_Pre_Off =>
                    if (SDTX_FIFO_Prog_r2 = '1') then                           -- SDTX_FIFO has space, the data in SDTX_FIFO is <= 2047
                        ctrl_state  <= S_Sd_Send_Off;
                        Sd_Rd       <= '1';
                        Sd_Rd_Addr  <= Addr_Ba & Addr_Row & Addr_Col;           -- Addr_Col no need control
                    else
                        ctrl_state  <= S_Sd_Pre_Off;
                        Sd_Rd       <= '0';
                    end if;

                when S_Sd_Send_Off =>
                    if (Sd_Rd_Ack = '1') then
                        ctrl_state  <= S_Sd_Ans_Off;
                        Sd_Rd       <= '0';
                    else
                        ctrl_state  <= S_Sd_Send_Off;
                        Sd_Rd       <= '1';
                    end if;
                    
                when S_Sd_Ans_Off =>
                    if (sd_cnt = 1024) then                                     -- read 1024 16bit data at a time
                        if (Addr_Row = Addr_Row_End) then                       -- col 1024, row 4096, store 2k*2k
                            ctrl_state  <= S_Sd_Idle;
                            Addr_Row    <= (others => '0');
                        else
                            ctrl_state  <= S_Sd_Pre_Off;
                            Addr_Row    <= Addr_Row + '1';
                        end if;
                        sd_cnt          <= 0;
                        SDTX_FIFO_Wr    <= '0';
                    else
                        ctrl_state      <= S_Sd_Ans_Off;
                        sd_cnt          <= sd_cnt + 1;
                        SDTX_FIFO_Wr    <= '1';
                        SDTX_FIFO_d     <= Sd_Rd_Data;
                    end if;
                --**************take 1024 k from sdram to ramA*****************
                when S_Sd_K_Pre_On =>
                    if (SDTX_FIFO_Prog_r2 = '1') then                           -- SDTX_FIFO has space, the data in SDTX_FIFO is <= 2047
                        ctrl_state  <= S_Sd_K_Send_On;
                        Sd_Rd       <= '1';
                        Sd_Rd_Addr  <= Addr_Ba & Addr_Row_K & Addr_Col;         -- Addr_Col no need control
                    else
                        ctrl_state  <= S_Sd_K_Pre_On;
                        Sd_Rd       <= '0';
                    end if;

                when S_Sd_K_Send_On =>
                    if (Sd_Rd_Ack = '1') then
                        ctrl_state  <= S_Sd_K_Ans_On;
                        Sd_Rd       <= '0';
                    else
                        ctrl_state  <= S_Sd_K_Send_On;
                        Sd_Rd       <= '1';
                    end if;

                when S_Sd_K_Ans_On =>
                    if (sd_cnt = 1024) then                                     -- read 1024 16bit data at a time
                        ctrl_state      <= S_Sd_B_Pre_On;
                        sd_cnt          <= 0;
                        SDK_RAM_Wr      <= "0";
                        Addr_Row_K      <= Addr_Row_K + '1';
                    else
                        ctrl_state      <= S_Sd_K_Ans_On;
                        sd_cnt          <= sd_cnt + 1;
                        SDK_RAM_Wr      <= "1";
                        SDK_RAM_d       <= Sd_Rd_Data;
                        SDK_RAM_Addra   <= CONV_STD_LOGIC_VECTOR(sd_cnt, 10);
                    end if;
                --**************take 1024 b from sdram to ramB*****************
                when S_Sd_B_Pre_On =>
                    ctrl_state  <= S_Sd_B_Send_On;
                    Sd_Rd       <= '1';
                    Sd_Rd_Addr  <= Addr_Ba & Addr_Row_B & Addr_Col;             -- Addr_Col no need control

                when S_Sd_B_Send_On =>
                    if (Sd_Rd_Ack = '1') then
                        ctrl_state  <= S_Sd_B_Ans_On;
                        Sd_Rd       <= '0';
                        Rd_Kb_En    <= '0';                                     -- change data cs
                    else
                        ctrl_state  <= S_Sd_B_Send_On;
                        Sd_Rd       <= '1';
                    end if;

                when S_Sd_B_Ans_On =>
                    if (sd_cnt = 1024) then                                     -- read 1024 16bit data at a time
                        ctrl_state      <= S_Sd_Pre_On;
                        sd_cnt          <= 0;
                        SDB_RAM_Wr      <= "0";
                        Addr_Row_B      <= Addr_Row_B + '1';
                        Addr_Ba         <= Addr_Ba_r;
                    else
                        ctrl_state      <= S_Sd_B_Ans_On;
                        sd_cnt          <= sd_cnt + 1;
                        SDB_RAM_Wr      <= "1";
                        SDB_RAM_d       <= Sd_Rd_Data;
                        SDB_RAM_Addra   <= CONV_STD_LOGIC_VECTOR(sd_cnt, 10);
                    end if;
                --**************take 1024 data from sdram to fifo with correction*****************
                when S_Sd_Pre_On =>
                    ctrl_state  <= S_Sd_Send_On;
                    Sd_Rd       <= '1';
                    Sd_Rd_Addr  <= Addr_Ba & Addr_Row & Addr_Col;               -- Addr_Col no need control

                when S_Sd_Send_On =>
                    if (Sd_Rd_Ack = '1') then
                        ctrl_state      <= S_Sd_Ans_On;
                        Sd_Rd           <= '0';
                        SDK_RAM_Addrb   <= SDK_RAM_Addrb + '1';
                    else
                        ctrl_state      <= S_Sd_Send_On;
                        Sd_Rd           <= '1';
                    end if;
                    
                when S_Sd_Ans_On =>
                    if (sd_cnt = 1028) then                                     -- read 1024 16bit data at a time
                        sd_cnt          <= 0;
                        if (Addr_Row = Addr_Row_End) then                       -- col 1024, row 4096, store 2k*2k
                            ctrl_state  <= S_Sd_Idle;
                            Addr_Row    <= (others => '0');                     -- reset 0
                            Addr_Row_K  <= CONV_STD_LOGIC_VECTOR(0, 13);        -- reset 0
                            Addr_Row_B  <= CONV_STD_LOGIC_VECTOR(4096, 13);     -- reset 4096
                            Corr_Status <= "01";                                -- nonuniform done
                        else
                            ctrl_state  <= S_Sd_K_Pre_On;
                            Addr_Ba     <= "00";
                            Addr_Row    <= Addr_Row + '1';
                            Rd_Kb_En    <= '1';                                 -- change k b cs
                        end if;
                    else
                        ctrl_state  <= S_Sd_Ans_On;
                        sd_cnt      <= sd_cnt + 1;
                    end if;
                    
                    case sd_cnt is
                        when 0 =>
                            Mul_Add_A       <= Sd_Rd_Data;
                            Mul_Add_B       <= SDK_RAM_q;
                            SDK_RAM_Addrb   <= SDK_RAM_Addrb + '1';
                            SDB_RAM_Addrb   <= SDB_RAM_Addrb + '1';
                        when 1 to 3 =>                                          -- sd_cnt = 5 Mul_Add_O is valid
                            Mul_Add_A       <= Sd_Rd_Data;
                            Mul_Add_B       <= SDK_RAM_q;
                            SDK_RAM_Addrb   <= SDK_RAM_Addrb + '1';
                            Mul_Add_C       <= SDB_RAM_q;
                            SDB_RAM_Addrb   <= SDB_RAM_Addrb + '1';
                        when 1024 =>
                            Mul_Add_C       <= SDB_RAM_q;
                            SDTX_FIFO_Wr    <= '1';
                            SDTX_FIFO_d     <= Mul_Add_O;
                        when 1025 to 1027 =>
                            SDTX_FIFO_Wr    <= '1';
                            SDTX_FIFO_d     <= Mul_Add_O;
                        when 1028 =>
                            SDTX_FIFO_Wr    <= '0';
                            SDK_RAM_Addrb   <= (others => '0');
                            SDB_RAM_Addrb   <= (others => '0');
                        when others =>
                            Mul_Add_A       <= Sd_Rd_Data;
                            Mul_Add_B       <= SDK_RAM_q;
                            SDK_RAM_Addrb   <= SDK_RAM_Addrb + '1';
                            Mul_Add_C       <= SDB_RAM_q;
                            SDB_RAM_Addrb   <= SDB_RAM_Addrb + '1';
                            SDTX_FIFO_Wr    <= '1';
                            SDTX_FIFO_d     <= Mul_Add_O;
                    end case;

                when others =>
                    ctrl_state      <= S_Sd_Idle;
            end case;
        end if;
    end process;

    ------------------------------------------------------------------------------
    -- send SDRAM fifo data to encode fifo data
    ------------------------------------------------------------------------------
    process(Clk_Sys, Rst_Sys) begin
        if (Rst_Sys = '0') then
            fifo_state      <= S_Idle;
            data_cnt        <= 0;
            Encode_En       <= '0';
            SDTX_FIFO_Req   <= '0';
            Line_Num        <= (others => '0');
            Encode_Data_in  <= (others => '0');
        elsif (Clk_Sys'event and Clk_Sys = '1') then
            case fifo_state is
                when S_Idle =>
                    if (Sign_Data = X"CC" and Commond_Data = X"BB" and Sen_Class = Cms_Class and Start_Tx_Flag_r4 = '1') then -- down command
                        fifo_state  <= S_Pre;
                    else
                        fifo_state  <= S_Idle;
                    end if;
                    data_cnt        <= 0;
                    Encode_En       <= '0';
                    SDTX_FIFO_Req   <= '0';
                    Line_Num        <= (others => '0');
                    Encode_Data_in  <= (others => '0');

                when S_Pre =>
                    if (SDTX_FIFO_Prog = '0' and Encode_Empty_r2 = '1') then    -- SDRAM fifo data > 2047, encode fifo empty
                        fifo_state  <= S_Head1;
                    else
                        fifo_state  <= S_Pre;
                    end if;

                when S_Head1 =>
                    fifo_state      <= S_Head2;
                    Encode_En       <= '1';
                    Encode_Data_in  <= Cms_Head;                                -- set head CMOSA EA, CMOSB EB

                when S_Head2 =>
                    fifo_state      <= S_Line1;
                    Encode_Data_in  <= X"55";                                   -- data packet

                when S_Line1 =>
                    fifo_state      <= S_Line2;
                    Encode_Data_in  <= Line_Num (15 downto 8);

                when S_Line2 =>
                    fifo_state      <= S_Data;
                    Encode_Data_in  <= Line_Num (7 downto 0);
                    SDTX_FIFO_Req   <= '1';                                     -- request SDRAM fifo

                when S_Data =>
                    if (data_cnt = 4095) then                                   -- 2048 pixels
                        fifo_state      <= S_Judge;
                        data_cnt        <= 0;
                        SDTX_FIFO_Req   <= '0';
                    else
                        fifo_state      <= S_Data;
                        data_cnt        <= data_cnt + 1;
                        SDTX_FIFO_Req   <= '1';
                    end if;
                    Encode_Data_in  <= SDTX_FIFO_q;

                when S_Judge =>
                    if (CONV_INTEGER(Line_Num) = 2047) then
                        fifo_state  <= S_Aux_Pre;
                        Line_Num    <= (others => '0');
                    else
                        fifo_state  <= S_Pre;
                        Line_Num    <= Line_Num + '1';
                    end if;
                    Encode_En       <= '0';
                    Encode_Data_in  <= (others => '0');

                when S_Aux_Pre =>
                    if (Encode_Empty_r2 = '1') then
                        fifo_state      <= S_Aux;
                        Encode_En       <= '1';
                        Encode_Data_in  <= Cms_Head;                            -- set head CMOSA EA, CMOSB EB
                    else
                        fifo_state      <= S_Aux_Pre;
                    end if;

                when S_Aux =>
                    if (aux_cnt = 23) then
                        fifo_state  <= S_Aux_D;
                        aux_cnt     <= 0;
                    else
                        fifo_state  <= S_Aux;
                        aux_cnt     <= aux_cnt + 1;
                    end if;
                    
                    case aux_cnt is
                        when 0 =>
                            Encode_Data_in  <= X"AA";                           -- auxiliary packet
                        when 1 =>
                            Encode_Data_in  <= Time_Code (47 downto 40);
                        when 2 =>
                            Encode_Data_in  <= Time_Code (39 downto 32);
                        when 3 =>
                            Encode_Data_in  <= Time_Code (31 downto 24);
                        when 4 =>
                            Encode_Data_in  <= Time_Code (23 downto 16);
                        when 5 =>
                            Encode_Data_in  <= Time_Code (15 downto 8);
                        when 6 =>
                            Encode_Data_in  <= Time_Code (7 downto 0);
                        when 7 =>
                            Encode_Data_in  <= Down_Frame;
                        when 8 =>
                            Encode_Data_in  <= Frame_Num - '1';
                        when 9 =>
                            Encode_Data_in  <= Gain_Mode;
                        when 10 =>
                            Encode_Data_in  <= Spi_Gaintop_Aux_r;
                        when 11 =>
                            Encode_Data_in  <= Exposure_Line (15 downto 8);
                        when 12 =>
                            Encode_Data_in  <= Exposure_Line (7 downto 0);
                        when 13 =>
                            Encode_Data_in  <= Sen_Temp_Aux_r (15 downto 8);
                        when 14 =>
                            Encode_Data_in  <= Sen_Temp_Aux_r (7 downto 0);
                        when 15 =>
                            Encode_Data_in  <= Corr_Mode;
                        when 16 =>
                            Encode_Data_in  <= Exp_Time_Code (47 downto 40);
                        when 17 =>
                            Encode_Data_in  <= Exp_Time_Code (39 downto 32);
                        when 18 =>
                            Encode_Data_in  <= Exp_Time_Code (31 downto 24);
                        when 19 =>
                            Encode_Data_in  <= Exp_Time_Code (23 downto 16);
                        when 20 =>
                            Encode_Data_in  <= Exp_Time_Code (15 downto 8);
                        when 21 =>
                            Encode_Data_in  <= Exp_Time_Code (7 downto 0);
                        when 22 =>
                            Encode_Data_in  <= (others => '0');
                        when others =>
                            null;
                    end case;

                when S_Aux_D =>
                    if (data_cnt = 4074) then               --4095+24+1=4100
                        fifo_state  <= S_Idle;
                        data_cnt    <= 0;
                    else
                        fifo_state  <= S_Aux_D;
                        data_cnt    <= data_cnt + 1;
                    end if;
                    Encode_Data_in  <= (others => '0');

                when others =>
                    fifo_state      <= S_Idle;
            end case;
        end if;
    end process;
end Behavioral;