library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pong_vga is
    Port (
        i_clk         : in  STD_LOGIC;                     -- 板子原始時脈 100MHz
        i_rst         : in  STD_LOGIC;                     -- 重置信號 (高電位有效)

        -- 左邊板子控制 (建議接按鈕，高電位有效)
        i_left_up     : in  STD_LOGIC;
        i_left_down   : in  STD_LOGIC;

        -- 右邊板子控制 (建議接按鈕，高電位有效)
        i_right_up    : in  STD_LOGIC;
        i_right_down  : in  STD_LOGIC;

        o_hsync       : out STD_LOGIC;                     -- 水平同步信號
        o_vsync       : out STD_LOGIC;                     -- 垂直同步信號
        o_red         : out STD_LOGIC_VECTOR(3 downto 0);  -- 紅色輸出
        o_green       : out STD_LOGIC_VECTOR(3 downto 0);  -- 綠色輸出
        o_blue        : out STD_LOGIC_VECTOR(3 downto 0);  -- 藍色輸出

        -- 分數輸出 (0~9，可接七段解碼器或另外的顯示模組)
        o_score_left  : out STD_LOGIC_VECTOR(3 downto 0);
        o_score_right : out STD_LOGIC_VECTOR(3 downto 0)
    );
end pong_vga;

architecture Behavioral of pong_vga is

    ------------------------------------------------------------------
    -- VGA 800x600 @ 60Hz 時序參數
    ------------------------------------------------------------------
    constant h_display : integer := 800;
    constant h_fp      : integer := 40;
    constant h_sync    : integer := 128;
    constant h_bp      : integer := 88;
    constant h_total   : integer := 1056;

    constant v_display : integer := 600;
    constant v_fp      : integer := 1;
    constant v_sync    : integer := 4;
    constant v_bp      : integer := 23;
    constant v_total   : integer := 628;

    constant clk_freq   : integer := 100_000_000;
    constant pixel_freq : integer := 39_791_680;
    constant acc_width  : integer := 32;

    signal acc      : unsigned(acc_width-1 downto 0) := (others => '0');
    signal pixel_en : STD_LOGIC := '0';
    signal h_count  : integer range 0 to h_total-1 := 0;
    signal v_count  : integer range 0 to v_total-1 := 0;

    ------------------------------------------------------------------
    -- 遊戲參數：板子 (paddle)
    ------------------------------------------------------------------
    constant paddle_width  : integer := 15;
    constant paddle_height : integer := 100;
    constant paddle_speed  : integer := 5;   -- 每個畫面刷新移動的像素數
    constant paddle_margin : integer := 30;  -- 板子離左右邊界的距離

    constant left_paddle_x  : integer := paddle_margin;
    constant right_paddle_x : integer := h_display - paddle_margin - paddle_width;

    signal paddle_left_y  : integer range 0 to v_display-paddle_height
                             := (v_display-paddle_height)/2;
    signal paddle_right_y : integer range 0 to v_display-paddle_height
                             := (v_display-paddle_height)/2;

    ------------------------------------------------------------------
    -- 遊戲參數：球 (ball)
    ------------------------------------------------------------------
    constant ball_size  : integer := 15;
    constant ball_speed : integer := 4;
    signal ball_x  : integer range 0 to h_display := h_display/2 - ball_size/2;
    signal ball_y  : integer range 0 to v_display := v_display/2 - ball_size/2;
    signal ball_dx : integer := ball_speed;   -- 水平速度 (可正可負)
    signal ball_dy : integer := ball_speed;   -- 垂直速度 (可正可負)

    ------------------------------------------------------------------
    -- 分數
    ------------------------------------------------------------------
    signal score_left  : integer range 0 to 9 := 0;
    signal score_right : integer range 0 to 9 := 0;

    signal game_over   : STD_LOGIC := '0';
    ------------------------------------------------------------------
    -- 每個畫面 (frame) 結束時產生一次脈波，遊戲邏輯以此更新
    ------------------------------------------------------------------
    signal frame_tick : STD_LOGIC := '0';

begin

    ------------------------------------------------------------------
    -- Process 0：除頻器 (產生 pixel_en 脈波)
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            acc      <= (others => '0');
            pixel_en <= '0';
        elsif rising_edge(i_clk) then
            if acc + pixel_freq >= clk_freq then
                acc      <= acc + pixel_freq - clk_freq;
                pixel_en <= '1';
            else
                acc      <= acc + pixel_freq;
                pixel_en <= '0';
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 1：水平計數器 h_count
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            h_count <= 0;
        elsif rising_edge(i_clk) then
            if pixel_en = '1' then
                if h_count = h_total - 1 then
                    h_count <= 0;
                else
                    h_count <= h_count + 1;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 2：垂直計數器 v_count
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            v_count <= 0;
        elsif rising_edge(i_clk) then
            if pixel_en = '1' then
                if h_count = h_total - 1 then
                    if v_count = v_total - 1 then
                        v_count <= 0;
                    else
                        v_count <= v_count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 3：水平同步信號 o_hsync 正極性
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            o_hsync <= '0';
        elsif rising_edge(i_clk) then
            if pixel_en = '1' then
                if (h_count >= h_display + h_fp) and
                   (h_count <  h_display + h_fp + h_sync) then
                    o_hsync <= '1';
                else
                    o_hsync <= '0';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 4：垂直同步信號 o_vsync 正極性
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            o_vsync <= '0';
        elsif rising_edge(i_clk) then
            if pixel_en = '1' then
                if (v_count >= v_display + v_fp) and
                   (v_count <  v_display + v_fp + v_sync) then
                    o_vsync <= '1';
                else
                    o_vsync <= '0';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 5：frame_tick - 每個畫面最後一個像素產生一次脈波
    -- 遊戲邏輯 (板子移動、球的運動) 都在這個脈波觸發時更新一次，
    -- 也就是每秒更新約 60 次
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            frame_tick <= '0';
        elsif rising_edge(i_clk) then
            if (pixel_en = '1') and (h_count = h_total-1) and (v_count = v_total-1) then
                frame_tick <= '1';
            else
                frame_tick <= '0';
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 6：左邊板子移動
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            paddle_left_y <= (v_display-paddle_height)/2;
        elsif rising_edge(i_clk) then
            if (frame_tick = '1') and (game_over = '0') then
                if i_left_up = '1' then
                    if paddle_left_y >= paddle_speed then
                        paddle_left_y <= paddle_left_y - paddle_speed;
                    else
                        paddle_left_y <= 0;
                    end if;
                elsif i_left_down = '1' then
                    if paddle_left_y <= v_display-paddle_height-paddle_speed then
                        paddle_left_y <= paddle_left_y + paddle_speed;
                    else
                        paddle_left_y <= v_display-paddle_height;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 7：右邊板子移動
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            paddle_right_y <= (v_display-paddle_height)/2;
        elsif rising_edge(i_clk) then
            if (frame_tick = '1') and (game_over = '0') then
                if i_right_up = '1' then
                    if paddle_right_y >= paddle_speed then
                        paddle_right_y <= paddle_right_y - paddle_speed;
                    else
                        paddle_right_y <= 0;
                    end if;
                elsif i_right_down = '1' then
                    if paddle_right_y <= v_display-paddle_height-paddle_speed then
                        paddle_right_y <= paddle_right_y + paddle_speed;
                    else
                        paddle_right_y <= v_display-paddle_height;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 8：球的運動、碰撞偵測與得分判斷
    ------------------------------------------------------------------
    process(i_clk, i_rst)
        variable next_x : integer;
        variable next_y : integer;
    begin
        if i_rst = '1' then
            ball_x      <= h_display/2 - ball_size/2;
            ball_y      <= v_display/2 - ball_size/2;
            ball_dx     <= ball_speed;
            ball_dy     <= ball_speed;
            score_left  <= 0;
            score_right <= 0;
            game_over   <= '0';
        elsif rising_edge(i_clk) then
            -- 遊戲已結束時，球與分數都凍結，直到 i_rst 重新開始
            if (frame_tick = '1') and (game_over = '0') then
                next_x := ball_x + ball_dx;
                next_y := ball_y + ball_dy;

                ----------------------------------------------------------
                -- 上下邊界反彈
                ----------------------------------------------------------
                if next_y <= 0 then
                    ball_y  <= 0;
                    ball_dy <= -ball_dy;
                elsif next_y >= v_display - ball_size then
                    ball_y  <= v_display - ball_size;
                    ball_dy <= -ball_dy;
                else
                    ball_y <= next_y;
                end if;

                ----------------------------------------------------------
                -- 左右邊界：撞板反彈 或 對方得分
                ----------------------------------------------------------
                if (ball_dx < 0) and (next_x <= left_paddle_x + paddle_width) and
                   (next_x >= left_paddle_x) and
                   (ball_y + ball_size >= paddle_left_y) and
                   (ball_y <= paddle_left_y + paddle_height) then
                    -- 撞到左邊板子，反彈往右
                    ball_x  <= left_paddle_x + paddle_width;
                    ball_dx <= ball_speed;

                elsif next_x <= 0 then
                    -- 沒接到，右邊玩家得分，球重置到中央
                    if score_right < 9 then
                        score_right <= score_right + 1;
                        if score_right + 1 = 9 then
                            -- 右邊拿到第9分，遊戲結束
                            game_over <= '1';
                        end if;
                    end if;
                    ball_x  <= h_display/2 - ball_size/2;
                    ball_y  <= v_display/2 - ball_size/2;
                    ball_dx <= ball_speed;

                elsif (ball_dx > 0) and (next_x + ball_size >= right_paddle_x) and
                      (next_x + ball_size <= right_paddle_x + paddle_width) and
                      (ball_y + ball_size >= paddle_right_y) and
                      (ball_y <= paddle_right_y + paddle_height) then
                    -- 撞到右邊板子，反彈往左
                    ball_x  <= right_paddle_x - ball_size;
                    ball_dx <= -ball_speed;

                elsif next_x >= h_display - ball_size then
                    -- 沒接到，左邊玩家得分，球重置到中央
                    if score_left < 9 then
                        score_left <= score_left + 1;
                        if score_left + 1 = 9 then
                            -- 左邊拿到第9分，遊戲結束
                            game_over <= '1';
                        end if;
                    end if;
                    ball_x  <= h_display/2 - ball_size/2;
                    ball_y  <= v_display/2 - ball_size/2;
                    ball_dx <= -ball_speed;

                else
                    ball_x <= next_x;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 9：分數輸出
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            o_score_left  <= "0000";
            o_score_right <= "0000";
        elsif rising_edge(i_clk) then
            o_score_left  <= STD_LOGIC_VECTOR(TO_UNSIGNED(score_left,  4));
            o_score_right <= STD_LOGIC_VECTOR(TO_UNSIGNED(score_right, 4));
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 10：畫面顏色輸出 (板子 / 球 / 中線 / 背景)
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            o_red   <= "0000";
            o_green <= "0000";
            o_blue  <= "0000";
        elsif rising_edge(i_clk) then
            if pixel_en = '1' then
                if (h_count < h_display) and (v_count < v_display) then

                    if game_over = '1' then
                        -- 遊戲結束：整個畫面顯示獲勝方顏色 (需要 i_rst 才能重新開始)
                        if score_left = 9 then
                            -- 左邊獲勝：綠色
                            o_red <= "0000"; o_green <= "1111"; o_blue <= "0000";
                        else
                            -- 右邊獲勝：紅色
                            o_red <= "1111"; o_green <= "0000"; o_blue <= "0000";
                        end if;

                    elsif (h_count >= left_paddle_x) and
                       (h_count <  left_paddle_x + paddle_width) and
                       (v_count >= paddle_left_y) and
                       (v_count <  paddle_left_y + paddle_height) then
                        -- 左邊板子：白色
                        o_red <= "1111"; o_green <= "1111"; o_blue <= "1111";

                    elsif (h_count >= right_paddle_x) and
                          (h_count <  right_paddle_x + paddle_width) and
                          (v_count >= paddle_right_y) and
                          (v_count <  paddle_right_y + paddle_height) then
                        -- 右邊板子：白色
                        o_red <= "1111"; o_green <= "1111"; o_blue <= "1111";

                    elsif (h_count >= ball_x) and (h_count < ball_x + ball_size) and
                          (v_count >= ball_y) and (v_count < ball_y + ball_size) then
                        -- 球：黃色
                        o_red <= "1111"; o_green <= "1111"; o_blue <= "0000";

                    elsif (h_count >= h_display/2 - 2) and (h_count < h_display/2 + 2) and
                          ((v_count mod 40) < 20) then
                        -- 中線：虛線灰色
                        o_red <= "0111"; o_green <= "0111"; o_blue <= "0111";

                    else
                        -- 背景：深藍色
                        o_red <= "0000"; o_green <= "0000"; o_blue <= "0010";
                    end if;

                else
                    -- 消隱區間：黑色
                    o_red   <= "0000";
                    o_green <= "0000";
                    o_blue  <= "0000";
                end if;
            end if;
        end if;
    end process;

end Behavioral;
