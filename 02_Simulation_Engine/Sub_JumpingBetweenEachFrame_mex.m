function [xe, ye, Xads, Yads, t_r] = Sub_JumpingBetweenEachFrame_mex(x0, y0, HashX, HashY, HashCount, DataTrans, TimeSeed)
%#codegen
    % 编译器内联，消除函数调用栈的压栈/退栈开销
    coder.inline('always');
    
    t_r = 0.0; % 满足编译占位
    
    % 物理参数解析
    t_tot = DataTrans(1); TI = DataTrans(2); t_a = DataTrans(3);
    tm_ads = DataTrans(4); k = DataTrans(5); jf = DataTrans(6);
    adR = DataTrans(7); vx = DataTrans(10); vy = DataTrans(11);
    DistMode = DataTrans(12);
    tjmp = 1 / jf;
    tclock = t_a;
    xe = x0; ye = y0; xb = x0; yb = y0;
    Xads = zeros(1, 0); Yads = zeros(1, 0);
    cell_size = 100.0;
    nx = 100.0; ny = 100.0;
    PrimeX = int32(73856093); PrimeY = int32(19349663);
    
    % 提取单精度的吸附半径平方，用于内层循环的混合精度比对
    adR_sq_single = single(adR * adR);
    
    if tclock < t_tot
        % 恢复动态数组：单帧吸附极少，空数组开销为 0
        Xads = zeros(1, 0); 
        Yads = zeros(1, 0);
        
        % 除法变乘法，提取常数
        inv_cell_size = 1.0 / cell_size;
        macro_size_x = nx * cell_size;
        macro_size_y = ny * cell_size;
        
        for i = 1:100000000
            dx = k * randn() + vx ;
            dy = k * randn() + vy ;
            xe = xb + dx;
            ye = yb + dy;
            
            % 采用乘法结合 floor，避开极慢的浮点除法
            ix_global = floor(xe * inv_cell_size);
            iy_global = floor(ye * inv_cell_size);
            
            % 【修复1】采用 mod 替代 rem，彻底杜绝 xe 跑入负半轴时导致的索引为负数崩溃
            ix = int32(mod(ix_global, nx)) + 1;
            iy = int32(mod(iy_global, ny)) + 1;
            MapIdx = mod(int32(ix_global) * PrimeX + int32(iy_global) * PrimeY + int32(TimeSeed), int32(4)) + 1;
            
            % 局部坐标
            local_x = mod(xe, macro_size_x);
            local_y = mod(ye, macro_size_y);
            if local_x < 0, local_x = local_x + macro_size_x; end
            if local_y < 0, local_y = local_y + macro_size_y; end
            
            count = HashCount(ix, iy, MapIdx);
            min_d_sq_single = single(inf);
            local_x_single = single(local_x);
            local_y_single = single(local_y);
            
            best_p = 1;
            % 核心计算区：保持单精度 SIMD 极速读取
            for p = 1 : count
                dx_val = local_x_single - single(HashX(p, ix, iy, MapIdx));
                dy_val = local_y_single - single(HashY(p, ix, iy, MapIdx));
                d_sq = dx_val * dx_val + dy_val * dy_val;
                if d_sq < min_d_sq_single
                    min_d_sq_single = d_sq;
                    best_p = p;
                end
            end
            
            if min_d_sq_single < adR_sq_single
                def_global_x = (xe - local_x) + double(HashX(best_p, ix, iy, MapIdx));
                def_global_y = (ye - local_y) + double(HashY(best_p, ix, iy, MapIdx));
                
                Xads = [Xads, def_global_x]; %#ok<AGROW>
                Yads = [Yads, def_global_y]; %#ok<AGROW>
                
                % 吸附时间逻辑分配正确，无需修改
                if DistMode == 1
                    t_ads = Sub_GeneratePowerLawWithMean(TI, tm_ads, 1);
                elseif DistMode == 2
                    t_ads = Sub_GenerateExponentialWithMean(tm_ads, 1);
                else
                    t_ads = Sub_GenerateUniformWithMean(tm_ads, 2*tm_ads, 1);
                end
                tclock = tclock + t_ads + tjmp;
            else
                tclock = tclock + tjmp;
            end
            
            xb = xe; yb = ye;
            if tclock >= t_tot
                t_r = tclock - t_tot;
                if t_r < 0, t_r = 0; end
                break;
            end
        end
        
    else
        t_r = tclock - t_tot;
        % 【致命修复点2】跨帧时必须返回分子停滞点 xe/ye，如果是 NaN 将导致长吸附轨迹被删除！
        Xads = xe; 
        Yads = ye;
    end
    
    if isempty(Xads), Xads = NaN; Yads = NaN; end
end
