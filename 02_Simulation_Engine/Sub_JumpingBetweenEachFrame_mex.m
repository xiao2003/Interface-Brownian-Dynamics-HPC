function [xe, ye, Xads, Yads, t_r] = Sub_JumpingBetweenEachFrame_mex(x0, y0, HashX, HashY, HashCount, DataTrans, TimeSeed)
%#codegen
% =========================================================================
% 极速静态查表 (Cache-Friendly 内存连续读取版)
% =========================================================================

t_tot = DataTrans(1); TI = DataTrans(2);    t_a = DataTrans(3);        
tm_ads = DataTrans(4); k = DataTrans(5);    jf = DataTrans(6);         
adR = DataTrans(7);    vx = DataTrans(10);  vy = DataTrans(11); 
DistMode = DataTrans(12);

tjmp = 1/jf;         
tclock = t_a;        
xe = x0; ye = y0; 
xb = x0; yb = y0;
t_r = 0;

coder.varsize('Xads', [1, Inf], [0, 1]);
coder.varsize('Yads', [1, Inf], [0, 1]);
Xads = zeros(1, 0); Yads = zeros(1, 0); 

L_block = 10000;
cell_size = 100;
nx = 100; 
ny = 100;

if tclock < t_tot
    for i = 1:100000000  
        % 1. 朗之万连续位移
        dx = k*randn + vx ;
        dy = k*randn + vy ;
        xe = xb + dx;
        ye = yb + dy;
        
        % 2. 宏观哈希：O(1) 计算所属地图区块
        Ix_macro = floor(xe / L_block);
        Iy_macro = floor(ye / L_block);
        MapIdx = mod(Ix_macro * 73856093 + Iy_macro * 19349663 + TimeSeed, 4) + 1;
        
        % 3. 局部哈希：O(1) 提取局部坐标与微观网格
        local_x = xe - Ix_macro * L_block;
        local_y = ye - Iy_macro * L_block;
        
        ix = floor(local_x / cell_size) + 1;
        iy = floor(local_y / cell_size) + 1;
        
        % 防越界截断
        if ix < 1, ix = 1; elseif ix > nx, ix = nx; end
        if iy < 1, iy = 1; elseif iy > ny, iy = ny; end
        
        % 4. 🚀 极限优化：缓存友好的连续内存读取
        % 注意这里的索引顺序已经完全匹配主程序！
        count = HashCount(ix, iy, MapIdx); 
        min_d_sq = inf;
        
        for p = 1:count
            % 因为 p 在第一维，在 C 语言底层这会变成绝对连续的指针平移
            dx_val = local_x - HashX(p, ix, iy, MapIdx);
            dy_val = local_y - HashY(p, ix, iy, MapIdx);
            d_sq = dx_val^2 + dy_val^2;
            if d_sq < min_d_sq
                min_d_sq = d_sq;
            end
        end
        
        % 5. CTRW 碰撞判据处理
        if min_d_sq < adR^2
            Xads = [Xads, xe]; %#ok<AGROW> 
            Yads = [Yads, ye]; %#ok<AGROW>
            
            switch DistMode
                case 1, t_ads = Sub_GeneratePowerLawWithMean(TI, tm_ads, 1);
                case 2, t_ads = Sub_GenerateExponentialWithMean(tm_ads, 1); 
                case 3, t_ads = Sub_GenerateUniformWithMean(tm_ads, 2*tm_ads, 1);    
                otherwise, t_ads = 0;
            end
            tclock = tclock + t_ads + tjmp;
        else
            tclock = tclock + tjmp;
        end
        
        xb = xe; yb = ye;
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