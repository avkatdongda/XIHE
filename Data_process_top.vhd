input （clk，--时钟
DATA(15 downto 0),--数据
valid,--有效标识
vcount(11 downto 0),--行坐标
hcount(11 downto 0),--列坐标
mode(2 downto 0)--模式
）

output
(DATA(15 downto 0),--数据
valid,--有效标识
vcount(11 downto 0),--行坐标
hcount(11 downto 0),--列坐标
mode(2 downto 0)--模式
)