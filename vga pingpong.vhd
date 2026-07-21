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
    -- VGA 800x600 @ 60Hz 時序參數 (與原始程式相同)
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

    signal next_ball_x     : integer;  -- 若本次移動，球下一步的 x 座標
    signal next_ball_y     : integer;  -- 若本次移動，球下一步的 y 座標
    signal hit_left_paddle  : STD_LOGIC;  -- 這一步是否會撞到左邊板子
    signal hit_right_paddle : STD_LOGIC;  -- 這一步是否會撞到右邊板子

    ------------------------------------------------------------------
    -- 分數
    ------------------------------------------------------------------
    signal score_left  : integer range 0 to 9 := 0;
    signal score_right : integer range 0 to 9 := 0;

    signal game_over   : STD_LOGIC := '0';
    
    type ball_state_t is (S_PLAY, S_SCORE_LEFT, S_SCORE_RIGHT, S_GAME_OVER);
    signal ball_state : ball_state_t := S_PLAY;

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
    -- Process 8- 算出球的下一步位置與撞板旗標
    ------------------------------------------------------------------
    process(ball_x, ball_y, ball_dx, ball_dy)
    begin
        next_ball_x <= ball_x + ball_dx;
        next_ball_y <= ball_y + ball_dy;

        if (ball_dx < 0) and (ball_x + ball_dx <= left_paddle_x + paddle_width) and
           (ball_x + ball_dx >= left_paddle_x) and
           (ball_y + ball_size >= paddle_left_y) and
           (ball_y <= paddle_left_y + paddle_height) then
            hit_left_paddle <= '1';
        else
            hit_left_paddle <= '0';
        end if;

        if (ball_dx > 0) and (ball_x + ball_dx + ball_size >= right_paddle_x) and
           (ball_x + ball_dx + ball_size <= right_paddle_x + paddle_width) and
           (ball_y + ball_size >= paddle_right_y) and
           (ball_y <= paddle_right_y + paddle_height) then
            hit_right_paddle <= '1';
        else
            hit_right_paddle <= '0';
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 9：FSM 狀態暫存器 - 只負責決定下一個狀態，不碰任何變數
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            ball_state <= S_PLAY;
        elsif rising_edge(i_clk) then
            if frame_tick = '1' then
                case ball_state is

                    when S_PLAY =>
                        if hit_left_paddle = '1' then
                            ball_state <= S_PLAY;              -- 撞到左板，繼續比賽
                        elsif next_ball_x <= 0 then
                            ball_state <= S_SCORE_RIGHT;        -- 沒接到，右邊得分
                        elsif hit_right_paddle = '1' then
                            ball_state <= S_PLAY;               -- 撞到右板，繼續比賽
                        elsif next_ball_x >= h_display - ball_size then
                            ball_state <= S_SCORE_LEFT;         -- 沒接到，左邊得分
                        else
                            ball_state <= S_PLAY;               -- 正常移動中
                        end if;

                    when S_SCORE_LEFT =>
                        if score_left + 1 >= 9 then
                            ball_state <= S_GAME_OVER;
                        else
                            ball_state <= S_PLAY;
                        end if;

                    when S_SCORE_RIGHT =>
                        if score_right + 1 >= 9 then
                            ball_state <= S_GAME_OVER;
                        else
                            ball_state <= S_PLAY;
                        end if;

                    when S_GAME_OVER =>
                        ball_state <= S_GAME_OVER;              -- 凍結，直到 i_rst

                end case;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 10：ball_x - 只負責更新球的水平位置
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            ball_x <= h_display/2 - ball_size/2;
        elsif rising_edge(i_clk) then
            if frame_tick = '1' then
                case ball_state is
                    when S_PLAY =>
                        if hit_left_paddle = '1' then
                            ball_x <= left_paddle_x + paddle_width;
                        elsif hit_right_paddle = '1' then
                            ball_x <= right_paddle_x - ball_size;
                        elsif (next_ball_x > 0) and (next_ball_x < h_display - ball_size) then
                            ball_x <= next_ball_x;
                        end if;
                        -- 若飛出邊界(即將得分)，這裡先不動，下個 frame_tick
                        -- 進入 S_SCORE_LEFT/RIGHT 後會被重置到中央
                    when S_SCORE_LEFT | S_SCORE_RIGHT =>
                        ball_x <= h_display/2 - ball_size/2;
                    when S_GAME_OVER =>
                        null;  -- 保持不動
                end case;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 11：ball_y - 只負責更新球的垂直位置
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            ball_y <= v_display/2 - ball_size/2;
        elsif rising_edge(i_clk) then
            if frame_tick = '1' then
                case ball_state is
                    when S_PLAY =>
                        if next_ball_y <= 0 then
                            ball_y <= 0;
                        elsif next_ball_y >= v_display - ball_size then
                            ball_y <= v_display - ball_size;
                        else
                            ball_y <= next_ball_y;
                        end if;
                    when S_SCORE_LEFT | S_SCORE_RIGHT =>
                        ball_y <= v_display/2 - ball_size/2;
                    when S_GAME_OVER =>
                        null;  -- 保持不動
                end case;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 12：ball_dx - 只負責更新球的水平速度(方向)
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            ball_dx <= ball_speed;
        elsif rising_edge(i_clk) then
            if frame_tick = '1' then
                case ball_state is
                    when S_PLAY =>
                        if hit_left_paddle = '1' then
                            ball_dx <= ball_speed;   -- 撞左板，反彈往右
                        elsif hit_right_paddle = '1' then
                            ball_dx <= -ball_speed;  -- 撞右板，反彈往左
                        end if;
                        -- 其餘情況(正常移動中)維持原方向
                    when S_SCORE_LEFT =>
                        ball_dx <= -ball_speed;  -- 重新發球方向
                    when S_SCORE_RIGHT =>
                        ball_dx <= ball_speed;   -- 重新發球方向
                    when S_GAME_OVER =>
                        null;
                end case;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 13：ball_dy - 只負責更新球的垂直速度(方向)
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            ball_dy <= ball_speed;
        elsif rising_edge(i_clk) then
            if frame_tick = '1' then
                case ball_state is
                    when S_PLAY =>
                        if (next_ball_y <= 0) or (next_ball_y >= v_display - ball_size) then
                            ball_dy <= -ball_dy;   -- 碰到上下邊界，反彈
                        end if;
                    when others =>
                        null;  -- 得分/結束狀態時垂直方向不變
                end case;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 14：score_left - 只負責左邊玩家的分數
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            score_left <= 0;
        elsif rising_edge(i_clk) then
            if (frame_tick = '1') and (ball_state = S_SCORE_LEFT) and (score_left < 9) then
                score_left <= score_left + 1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 15：score_right - 只負責右邊玩家的分數
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            score_right <= 0;
        elsif rising_edge(i_clk) then
            if (frame_tick = '1') and (ball_state = S_SCORE_RIGHT) and (score_right < 9) then
                score_right <= score_right + 1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 16：game_over - 只負責記錄遊戲是否已經結束
    ------------------------------------------------------------------
    process(i_clk, i_rst)
    begin
        if i_rst = '1' then
            game_over <= '0';
        elsif rising_edge(i_clk) then
            if frame_tick = '1' then
                if (ball_state = S_SCORE_LEFT  and score_left  + 1 >= 9) or
                   (ball_state = S_SCORE_RIGHT and score_right + 1 >= 9) then
                    game_over <= '1';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Process 17：分數輸出 
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
    -- Process 18：畫面顏色輸出 (板子 / 球 / 中線 / 背景)
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
