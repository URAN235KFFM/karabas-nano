-------------------------------------------------------------------[16.07.2019]
-- VIDEO Pentagon mode
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity video is
	port (
		CLK		: in std_logic;							-- system clock
		ENA7		: in std_logic;							-- 7MHz ticks
		BORDER	: in std_logic_vector(2 downto 0);	-- bordr color (port #xxFE)
		DI			: in std_logic_vector(7 downto 0);	-- video data from memory
		INT		: out std_logic;
		ATTR_O	: out std_logic_vector(7 downto 0);
		A			: out std_logic_vector(13 downto 0);
		BLANK		: out std_logic;							-- BLANK
		RGB		: out std_logic_vector(2 downto 0);	-- RGB
		I			: out std_logic; -- brightness
		HSYNC		: out std_logic;
		VSYNC		: out std_logic;
		
		VBUS_MODE : in std_logic := '0';
		VID_RD 	 : in std_logic := '0';

		HCNT0		: out std_logic;
		HCNT1		: out std_logic
		);
end entity;

architecture rtl of video is

	signal invert   : unsigned(4 downto 0) := "00000";

	signal chr_col_cnt : unsigned(2 downto 0) := "000"; -- Character column counter
	signal chr_row_cnt : unsigned(2 downto 0) := "000"; -- Character row counter

	signal hor_cnt  : unsigned(5 downto 0) := "000000"; -- Horizontal char counter
	signal ver_cnt  : unsigned(5 downto 0) := "000000"; -- Vertical char counter
	
	signal attr     : std_logic_vector(7 downto 0);
	signal bitmap    : std_logic_vector(7 downto 0);
	
	signal paper_r  : std_logic;
	signal blank_r  : std_logic;
	signal attr_r   : std_logic_vector(7 downto 0);

--	signal shift_r  : std_logic_vector(7 downto 0);

	signal paper     : std_logic;
	signal pixel 	  : std_logic;
	signal shift_load : std_logic;
	
begin

	-- sync, counters
	process( CLK, ENA7, chr_col_cnt, hor_cnt, chr_row_cnt, ver_cnt)
	begin
		if CLK'event and CLK = '1' then
		
			if ENA7 = '1' then
			
				if chr_col_cnt = 7 then
				
					if hor_cnt = 55 then
						hor_cnt <= (others => '0');
					else
						hor_cnt <= hor_cnt + 1;
					end if;
					
					if hor_cnt = 39 then
						if chr_row_cnt = 7 then
							if ver_cnt = 39 then
								ver_cnt <= (others => '0');
								invert <= invert + 1;
							else
								ver_cnt <= ver_cnt + 1;
							end if;
						end if;
						chr_row_cnt <= chr_row_cnt + 1;
					end if;
				end if;

				-- h/v sync

				if chr_col_cnt = 7 then

					if (hor_cnt(5 downto 2) = "1010") then 
						HSYNC <= '0';
					else 
						HSYNC <= '1';
					end if;
					
					if ver_cnt /= 31 then
						VSYNC <= '1';
					elsif chr_row_cnt = 3 or chr_row_cnt = 4 or ( chr_row_cnt = 5 and ( hor_cnt >= 40 or hor_cnt < 12 ) ) then
						VSYNC<= '0';
					else 
						VSYNC <= '1';
					end if;
					
				end if;
			
				-- PENTAGON int
				if chr_col_cnt = 6 and hor_cnt(2 downto 0) = "111" then
					if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 3) = "100" then
						INT <= '0';
					else
						INT <= '1';
					end if;
				end if;

				chr_col_cnt <= chr_col_cnt + 1;
			end if;
		end if;
	end process;

	-- r/g/b/i
	process( CLK, ENA7, paper_r, pixel, attr_r, invert, blank_r, BORDER )
	begin
		if CLK'event and CLK = '1' then
			if (ENA7 = '1') then 
				if paper_r = '0' then -- paper				
					-- standard RGB
					if( pixel xor ( attr_r(7) and invert(4) ) ) = '1' then -- fg pixel
						if (attr_r(6) = '1' and attr_r(2 downto 0) = "000") then 
							RGB <= "000";
							I <= '0';
						else
							RGB(0) <= attr_r(0);
							RGB(2) <= attr_r(1);
							RGB(1) <= attr_r(2);
							I <= attr_r(6);
						end if;
					else	-- bg pixel
						if (attr_r(6) = '1' and attr_r(5 downto 3) = "000") then 
							RGB <= "000";
							I <= '0';
						else
							RGB(0) <= attr_r(3);
							RGB(2) <= attr_r(4);
							RGB(1) <= attr_r(5);
							I <= attr_r(6);
						end if;
					end if;
				else -- not paper
					if blank_r = '0' then
						-- blank
						RGB <= "000";
						I <= '0';
					else -- std border
						RGB(0) <= BORDER(0);
						RGB(2) <= BORDER(1);
						RGB(1) <= BORDER(2);
						I <= '0';
					end if;
				end if;
			end if;
		end if;
	end process;

	-- paper, blank
	process( CLK, ENA7, chr_col_cnt, hor_cnt, ver_cnt, paper )
	begin
		if CLK'event and CLK = '1' then
			if ENA7 = '1' then
				if chr_col_cnt = 7 then
					if ((hor_cnt(5 downto 0) > 38 and hor_cnt(5 downto 0) < 48) or ver_cnt(5 downto 1) = 15) then
						blank_r <= '0';
					else 
						blank_r <= '1';
					end if;							
					paper_r <= paper;
				end if;
			end if;
		end if;
	end process;	
	
		
	-- shift register parallel load signal
	process (CLK, ENA7)
	begin
		if CLK'event and CLK='1' then 
			if ENA7 = '1' then 
				if chr_col_cnt = 7 then 
					shift_load <= '1';
				else 
					shift_load <= '0';
				end if;
			end if;
		end if;
	end process;
	
	-- shift register (LPM_SHIFTREG)
	USR: entity work.shift_out
	port map(
		clock => ENA7,
		enable => '1',
		data => bitmap,
		load => shift_load,
		shiftout => pixel
	);
	
	-- attribute latch
	process( CLK, ENA7, chr_col_cnt, attr )
	begin
		if CLK'event and CLK = '1' then
			if ENA7 = '1' then
				if chr_col_cnt = 7 then
					attr_r <= attr;
				end if;
			end if;
		end if;
	end process;
	
	-- video mem read cycle
	process (CLK, ENA7, chr_col_cnt, ver_cnt, chr_row_cnt, hor_cnt, DI)
	begin 
		if (CLK'event and CLK = '1') then 
			if (chr_col_cnt(0) = '1' and ENA7 = '0') then
				if VBUS_MODE = '1' then
					if VID_RD = '0' then 
						bitmap <= DI;
					else 
						attr <= DI;
					end if;
				end if;
			end if;
		end if;
	end process;
	
	A <= 
		-- data address
		std_logic_vector( '0' & ver_cnt(4 downto 3) & chr_row_cnt & ver_cnt(2 downto 0) & hor_cnt(4 downto 0)) when VBUS_MODE = '1' and VID_RD = '0' else 
		-- standard attribute address
		std_logic_vector( "0110" & ver_cnt(4 downto 0) & hor_cnt(4 downto 0));

	ATTR_O	<= attr_r;
	BLANK	<= blank_r;
	paper <= '0' when hor_cnt(5) = '0' and ver_cnt(5) = '0' and ( ver_cnt(4) = '0' or ver_cnt(3) = '0' ) else '1';

	HCNT0 <= chr_col_cnt(0);
	HCNT1 <= chr_col_cnt(1);

end architecture;