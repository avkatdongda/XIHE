----------------------------------------------------------------------------------
-- Company:         CIOMP
-- Engineer:        WangZheng
-- Create Date:     14:47:22 01/06/2020
-- Module Name:     SDRAM_CTRL - Behavioral
-- Project Name:    SEN_IMA
-- Target Devices:  Virtex-4 xqr4vsx55-10cf1140
-- Tool versions:   ISE 14.7
-- Description:     sdram_rx receive the 4 fifo image data into a rx fifo
--                  sdram_drive drive the sdram for writing and reading (speed 7.5ns)
--                  sdram_tx transmit the tx fifo image data to a tx fifo
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

entity SDRAM_CTRL is
    generic (
        Cms_Class                   : STD_LOGIC_VECTOR (7 downto 0):= X"AA";    -- set class CMOSA AA, CMOSB 55
        Cms_Head                    : STD_LOGIC_VECTOR (7 downto 0):= X"EA");   -- set head CMOSA EA, CMOSB EB
    port (
        ---------CLOCKING---------
        Clk_Sys                     : in  STD_LOGIC;                            -- system clk 80MHz
        Rst_Sys                     : in  STD_LOGIC;                            -- Clk_Sys correspond rst signal
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
        ---------SERIAL_CMD---------
        Gain_Mode                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- sensor Gain_Mode HG/LG 11H/22H, default 00H
        Sign_Data                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- Sign_Data AAH(thermal) BBH(set) CCH(ctrl) DDH(inquire)
        Commond_Data                : in  STD_LOGIC_VECTOR (7 downto 0);        -- Commond_Data 11H 22H 44H 55H 88H AAH BBH correspond different Sign_Data
        Frame_Num                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- Frame_Num 01H~14H, default 01H.
        Exposure_Line               : in  STD_LOGIC_VECTOR (15 downto 0);       -- Exposure_Line 0000H~FFFFH default 0100H
        Sen_Class                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- down CMOSA or CMOSB, CMOSA AA, CMOSB 55
        Time_Code                   : in  STD_LOGIC_VECTOR (47 downto 0);       -- system time code, 0~FFFFFFH
        Down_Frame                  : in  STD_LOGIC_VECTOR (7 downto 0);        -- the frame numble of down
        Corr_Mode                   : in  STD_LOGIC_VECTOR (7 downto 0);        -- down correction mode, on 0xAA, off 0x55
        Corr_Status                 : out STD_LOGIC_VECTOR (1 downto 0);        -- the status of nonuniform correction, "10" is working, "01" none
        Store_Status                : out STD_LOGIC_VECTOR (1 downto 0);        -- store status, "10" is working, "01" none
        ---------NOF_CTL---------
        Nor_FIFO_Req                : out STD_LOGIC;                            -- nor fifo receive request
        Nor_FIFO_q                  : in  STD_LOGIC_VECTOR (15 downto 0);       -- nor fifo output 16bit data
        Nor_FIFO_Prog_Empty         : in  STD_LOGIC;                            -- nor fifo fifo prog empty
        ---------SEN_DRIVE---------
        Image_Out                   : in  STD_LOGIC;                            -- pull high when the image's output is valid
        ---------SEN_CTRL---------
        Start_Tx_Flag               : in  STD_LOGIC;                            -- the command of send instruction
        ---------SEN_SPI---------
        Sen_Temp_Aux                : in  STD_LOGIC_VECTOR (15 downto 0);       -- the temperature of sensor in auxiliary packet
        Spi_Gaintop_Aux             : in  STD_LOGIC_VECTOR (7 downto 0);        -- read spi low gain register in auxiliary packet
        Spi_Gainbot_Aux             : in  STD_LOGIC_VECTOR (7 downto 0);        -- read spi high gain register in auxiliary packet
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
        ---------IMA_TX---------
        Encode_Empty                : in  STD_LOGIC;                            -- '1' when encode fifo is empty
        Encode_En                   : out STD_LOGIC;                            -- Encode_Data_in enable
        Encode_Data_in              : out STD_LOGIC_VECTOR (7 downto 0));       -- encode fifo data signal input
end SDRAM_CTRL;

architecture Behavioral of SDRAM_CTRL is

    -- SDRAM_RX
    signal  Sd_Wr                   : STD_LOGIC;                                -- the enable signal of starting writing
    signal  Sd_Wr_Cs                : STD_LOGIC_VECTOR (7 downto 0);            -- sdram chip select signal, write mode
    signal  Sd_Wr_Addr              : STD_LOGIC_VECTOR (24 downto 0);           -- BA(2)+ROW(13)+COL(10) address, COL is.all 0, BA is chip selection, 00 01 10 11, correspond 8192 row. 2k*2k storage 1 selection 
    signal  Sd_Wr_Data              : STD_LOGIC_VECTOR (15 downto 0);           -- the data signal of outputting
    -- SDRAM_DRIVE
    signal  Sd_Wr_Ack               : STD_LOGIC;                                -- the acknowledge signal after receiving Sd_Wr
    signal  Sd_Wr_End               : STD_LOGIC;                                -- the end signal of writing data
    signal  Sd_Rd_Ack               : STD_LOGIC;                                -- the acknowledge signal after receiving Sd_Rd
    signal  Sd_Rd_Data              : STD_LOGIC_VECTOR (15 downto 0);           -- the data signal of reading
    -- SDRAM_TX
    signal  Sd_Rd                   : STD_LOGIC;                                -- the enable signal of starting reading
    signal  Sd_Rd_Cs                : STD_LOGIC_VECTOR (7 downto 0);            -- sdram chip select signal, read mode
    signal  Sd_Rd_Addr              : STD_LOGIC_VECTOR (24 downto 0);           -- BA(2)+ROW(A0~A12)+COL(A0~A9) address

    component SDRAM_RX is
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
    end component;

    component SDRAM_DRIVE is
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
    end component;
    
    component SDRAM_TX is
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
    end component;
    
begin

    C61 : SDRAM_RX
    port map (
        Clk_Sdr                     => Clk_Sdr,
        Rst_Sdr                     => Rst_Sdr,
        Store_Status                => Store_Status,
        Gain_Mode                   => Gain_Mode,
        Nor_FIFO_Req                => Nor_FIFO_Req,
        Nor_FIFO_q                  => Nor_FIFO_q,
        Nor_FIFO_Prog_Empty         => Nor_FIFO_Prog_Empty,
        Image_Out                   => Image_Out,
        RX_FIFO_q_Chan1             => RX_FIFO_q_Chan1,
        RX_FIFO_q_Chan2             => RX_FIFO_q_Chan2,
        RX_FIFO_q_Chan3             => RX_FIFO_q_Chan3,
        RX_FIFO_q_Chan4             => RX_FIFO_q_Chan4,
        RX_FIFO_q_Chan5             => RX_FIFO_q_Chan5,
        RX_FIFO_q_Chan6             => RX_FIFO_q_Chan6,
        RX_FIFO_q_Chan7             => RX_FIFO_q_Chan7,
        RX_FIFO_q_Chan8             => RX_FIFO_q_Chan8,
        RX_FIFO_Req_Chan1           => RX_FIFO_Req_Chan1,
        RX_FIFO_Req_Chan2           => RX_FIFO_Req_Chan2,
        RX_FIFO_Req_Chan3           => RX_FIFO_Req_Chan3,
        RX_FIFO_Req_Chan4           => RX_FIFO_Req_Chan4,
        RX_FIFO_Req_Chan5           => RX_FIFO_Req_Chan5,
        RX_FIFO_Req_Chan6           => RX_FIFO_Req_Chan6,
        RX_FIFO_Req_Chan7           => RX_FIFO_Req_Chan7,
        RX_FIFO_Req_Chan8           => RX_FIFO_Req_Chan8,
        RX_FIFO_Prog_Chan1          => RX_FIFO_Prog_Chan1,
        RX_FIFO_Prog_Chan5          => RX_FIFO_Prog_Chan5,
        Self_Image_Out              => Self_Image_Out,
        Sd_Wr_Ack                   => Sd_Wr_Ack,
        Sd_Wr_End                   => Sd_Wr_End,
        Sd_Wr                       => Sd_Wr,
        Sd_Wr_Cs                    => Sd_Wr_Cs,
        Sd_Wr_Addr                  => Sd_Wr_Addr,
        Sd_Wr_Data                  => Sd_Wr_Data);

    C62 : SDRAM_DRIVE
    port map (
        Clk_Sdr                     => Clk_Sdr,
        Rst_Sdr                     => Rst_Sdr,
        SD_DQ                       => SD_DQ,
        SD_A                        => SD_A,
        SD_BA                       => SD_BA,
        SD_RAS                      => SD_RAS,
        SD_CAS                      => SD_CAS,
        SD_WE                       => SD_WE,
        SD_CKE                      => SD_CKE,
        SD_CS                       => SD_CS,
        SD_UDQM                     => SD_UDQM,
        SD_LDQM                     => SD_LDQM,
        Sd_Wr_Ack                   => Sd_Wr_Ack,
        Sd_Wr_End                   => Sd_Wr_End,
        Sd_Wr                       => Sd_Wr,
        Sd_Wr_Cs                    => Sd_Wr_Cs,
        Sd_Wr_Addr                  => Sd_Wr_Addr,
        Sd_Wr_Data                  => Sd_Wr_Data,
        Sd_Rd_Ack                   => Sd_Rd_Ack,
        Sd_Rd                       => Sd_Rd,
        Sd_Rd_Cs                    => Sd_Rd_Cs,
        Sd_Rd_Addr                  => Sd_Rd_Addr,
        Sd_Rd_Data                  => Sd_Rd_Data);

    C63 : SDRAM_TX
    generic map (
        Cms_Class                   => Cms_Class,
        Cms_Head                    => Cms_Head)
    port map (
        Clk_Sdr                     => Clk_Sdr,
        Rst_Sdr                     => Rst_Sdr,
        Clk_Sys                     => Clk_Sys,
        Rst_Sys                     => Rst_Sys,
        Sign_Data                   => Sign_Data,
        Commond_Data                => Commond_Data,
        Frame_Num                   => Frame_Num,
        Exposure_Line               => Exposure_Line,
        Gain_Mode                   => Gain_Mode,
        Sen_Class                   => Sen_Class,
        Time_Code                   => Time_Code,
        Down_Frame                  => Down_Frame,
        Corr_Mode                   => Corr_Mode,
        Corr_Status                 => Corr_Status,
        Image_Out                   => Image_Out,
        Sen_Temp_Aux                => Sen_Temp_Aux,
        Spi_Gaintop_Aux             => Spi_Gaintop_Aux,
        Spi_Gainbot_Aux             => Spi_Gainbot_Aux,
        Start_Tx_Flag               => Start_Tx_Flag,
        Sd_Rd_Ack                   => Sd_Rd_Ack,
        Sd_Rd                       => Sd_Rd,
        Sd_Rd_Cs                    => Sd_Rd_Cs,
        Sd_Rd_Addr                  => Sd_Rd_Addr,
        Sd_Rd_Data                  => Sd_Rd_Data,
        Encode_Empty                => Encode_Empty,
        Encode_En                   => Encode_En,
        Encode_Data_in              => Encode_Data_in);
end Behavioral;