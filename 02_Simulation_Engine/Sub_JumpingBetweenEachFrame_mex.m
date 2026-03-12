function [xe, ye, Xads, Yads, t_r] = Sub_JumpingBetweenEachFrame_mex(x0, y0, XYd, DataTrans)
%#codegen
% =========================================================================
% 极速 Linked-Cell (O(1)哈希链表) 单分子表面物理吸附积分引擎
% 请务必使用 MATLAB Coder 将此文件编译为 mex 格式以获得极致加速。
% =========================================================================

% 解析外部物理与离散化参数
t_tot = DataTrans(1); TI = DataTrans(2);    t_a = DataTrans(3);        
tm_ads = DataTrans(4); k = DataTrans(5);    jf = DataTrans(6);         
adR = DataTrans(7);    vx = DataTrans(10);  vy = DataTrans(11); 
DistMode = DataTrans(12);

Xd = XYd(:,1); Yd = XYd(:,2);
num_defects = numel(Xd);

tjmp = 1/jf;         % 每次随机游走的时间步长
tclock = t_a;        % 本局初始时钟
xe = x0; ye = y0; 
xb = x0; yb = y0;
t_r = 0;

% 预分配变长数组的内存范围 (针对 Coder 编译的强制要求)
coder.varsize('Xads', [1, Inf], [0, 1]);
coder.varsize('Yads', [1, Inf], [0, 1]);
Xads = zeros(1, 0); Yads = zeros(1, 0); 

if num_defects == 0
    Xads = NaN; Yads = NaN; t_r = max(0, tclock - t_tot);
    return;
end

% --- [核心算法] 高性能 Linked-Cell 链表构建 ---
cell_size = max([100, 4*adR, 4*k]); % 确保元胞大小足以囊括单步跳跃与吸附半径
minX = min(Xd); maxX = max(Xd);
minY = min(Yd); maxY = max(Yd);
nx = floor((maxX - minX) / cell_size) + 1;
ny = floor((maxY - minY) / cell_size) + 1;

% 哈希头指针与链表主体
head = zeros(nx * ny, 1);
list = zeros(num_defects, 1);

for i = 1:num_defects
    ix = floor((Xd(i) - minX) / cell_size) + 1;
    iy = floor((Yd(i) - minY) / cell_size) + 1;
    ix = max(1, min(nx, ix)); iy = max(1, min(ny, iy));
    idx = (ix - 1) * ny + iy;
    list(i) = head(idx); 
    head(idx) = i;
end

% --- 蒙特卡洛积分：布朗动力学与对流输运方程叠加 ---
if tclock < t_tot
    for i = 1:100000000  % 防死循环的安全上限
        % 考虑对流-扩散方程 (Langevin 方程的离散形式)
        dx = k*randn + vx ;
        dy = k*randn + vy ;
        xe = xb + dx;
        ye = yb + dy;
        
        ixp = floor((xe - minX) / cell_size) + 1;
        iyp = floor((ye - minY) / cell_size) + 1;
        min_d_sq = inf;
        
        % O(1) 搜索：只检查自身及周围共 9 个元胞内的缺陷点
        for dix = -1:1
            for diy = -1:1
                cx = ixp + dix; cy = iyp + diy;
                if cx >= 1 && cx <= nx && cy >= 1 && cy <= ny
                    curr_defect = head((cx - 1) * ny + cy);
                    while curr_defect > 0
                        dx_val = xe - Xd(curr_defect);
                        dy_val = ye - Yd(curr_defect);
                        d_sq = dx_val^2 + dy_val^2;
                        if d_sq < min_d_sq
                            min_d_sq = d_sq;
                        end
                        curr_defect = list(curr_defect);
                    end
                end
            end
        end
        
        % 碰撞吸附判据
        if min_d_sq < adR^2
            Xads = [Xads, xe]; %#ok<AGROW> 
            Yads = [Yads, ye]; %#ok<AGROW>
            
            % 处理表面滞留时间 (Residence time) 的统计物理分布
            switch DistMode
                case 1, t_ads = Sub_GeneratePowerLawWithMean(TI, tm_ads, 1);
                case 2, t_ads = Sub_GenerateExponentialWithMean(tm_ads, 1); 
                case 3, t_ads = Sub_GenerateUniformWithMean(tm_ads, 2*TI, 1);    
                otherwise, t_ads = 0;
            end
            tclock = tclock + t_ads + tjmp;
        else
            tclock = tclock + tjmp;
        end
        
        xb = xe; yb = ye;
        % 超过本帧采样时间，结算残留时间并退出
        if tclock >= t_tot
            t_r = tclock - t_tot;
            break;
        end
    end
    if isempty(Xads), Xads = NaN; Yads = NaN; end
else
    t_r = tclock - t_tot;
    Xads = xe; Yads = ye;
end
end