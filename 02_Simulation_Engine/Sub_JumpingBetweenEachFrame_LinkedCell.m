function [xe, ye, Xads, Yads, t_r, Tads_list] = Sub_JumpingBetweenEachFrame_LinkedCell( ...
    x0, y0, AllX, AllY, CellStart, CellCount, DataTrans, TimeSeed, ...
    L_block, cell_size, nx_i, ny_i)

    coder.inline('always');
    
    % ---------------------------
    % 基础初始化与动态内存解锁
    % ---------------------------
    coder.varsize('Xads', [1, inf], [0, 1]);
    coder.varsize('Yads', [1, inf], [0, 1]);
    coder.varsize('Tads_list', [1, inf], [0, 1]);

    xe = x0;
    ye = y0;
    xb = x0;
    yb = y0;
    t_r = 0.0;

    Xads = zeros(1, 0);
    Yads = zeros(1, 0);
    Tads_list = zeros(1, 0); 

    % ---------------------------
    % 参数解析
    % ---------------------------
    t_tot    = DataTrans(1);   
    TI       = DataTrans(2);
    t_a      = DataTrans(3);   
    tm_ads   = DataTrans(4);
    k        = DataTrans(5);
    jf       = DataTrans(6);
    adR      = DataTrans(7);
    noise_flag = DataTrans(8);
    frame_j  = DataTrans(9);  
    vx       = DataTrans(10);
    vy       = DataTrans(11);
    DistMode = DataTrans(12);

    if frame_j == 1
        if noise_flag == 0
            % 【模式 1：控制变量（相同序列）】
            % 所有独立任务使用绝对一样的基础种子
            rng(uint32(TimeSeed), 'twister');
        else
            % 【模式 2：真随机（独立序列）】
            % 将主种子与唯一的 noise_flag (即 taskID) 乘上质数后深度绑定
            % 保证成百上千个并行任务拥有绝对独立且不重合的底噪
            unique_seed = uint32(TimeSeed) + uint32(noise_flag * 19349663); 
            rng(unique_seed, 'twister');
        end
    end

    tjmp   = 1.0 / jf;
    tclock = t_a;
    
    PrimeX = int32(73856093);
    PrimeY = int32(19349663);
    adR_sq = adR * adR;

    % ---------------------------
    % (后面的代码保持你原来的不变即可)
    % ---------------------------

    % ---------------------------
    % 跨帧被困判定 (修复了数组维度不匹配的 Bug)
    % ---------------------------
    if tclock >= t_tot
        t_r = tclock - t_tot;
        Xads = xe;
        Yads = ye;
        Tads_list = NaN; % <--- 【修复核心】补齐维度为1，用 NaN 占位防止 Worker 崩溃
        return;
    end

    % ---------------------------
    % 本帧推进
    % ---------------------------
    for stepIter = 1:100000000
        dx = k * randn() + vx;
        dy = k * randn() + vy;

        xe = xb + dx;
        ye = yb + dy;

        bx_global = floor(xe / L_block);
        by_global = floor(ye / L_block);

        local_x = mod(xe, L_block);
        local_y = mod(ye, L_block);

        if local_x < 0.0, local_x = local_x + L_block; end
        if local_y < 0.0, local_y = local_y + L_block; end

        ix_i = int32(floor(local_x / cell_size)) + int32(1);
        iy_i = int32(floor(local_y / cell_size)) + int32(1);

        if ix_i < int32(1), ix_i = int32(1); elseif ix_i > nx_i, ix_i = nx_i; end
        if iy_i < int32(1), iy_i = int32(1); elseif iy_i > ny_i, iy_i = ny_i; end

        MapIdx_i = mod(int32(bx_global) * PrimeX + int32(by_global) * PrimeY + int32(TimeSeed), int32(4)) + int32(1);

        best_d_sq = inf;
        best_x = 0.0;
        best_y = 0.0;

        for dix = -1:1
            for diy = -1:1
                ixn_i = ix_i + int32(dix);
                iyn_i = iy_i + int32(diy);

                shift_x = 0.0;
                shift_y = 0.0;

                if ixn_i < int32(1)
                    ixn_i = ixn_i + nx_i; shift_x = -L_block;
                elseif ixn_i > nx_i
                    ixn_i = ixn_i - nx_i; shift_x =  L_block;
                end

                if iyn_i < int32(1)
                    iyn_i = iyn_i + ny_i; shift_y = -L_block;
                elseif iyn_i > ny_i
                    iyn_i = iyn_i - ny_i; shift_y =  L_block;
                end

                s_u = CellStart(ixn_i, iyn_i, MapIdx_i);
                c_u = CellCount(ixn_i, iyn_i, MapIdx_i);

                if c_u == uint32(0), continue; end

                s_d = double(s_u);
                c_d = double(c_u);

                for p = 0:(c_d - 1)
                    idx_d = s_d + p;
                    xcand = AllX(idx_d) + shift_x;
                    ycand = AllY(idx_d) + shift_y;

                    dxv = local_x - xcand;
                    dyv = local_y - ycand;
                    d2 = dxv * dxv + dyv * dyv;

                    if d2 < best_d_sq
                        best_d_sq = d2;
                        best_x = xcand;
                        best_y = ycand;
                    end
                end
            end
        end

       % -----------------------
        % 吸附判定
        % -----------------------
        if best_d_sq < adR_sq
            def_global_x = (xe - local_x) + best_x;
            def_global_y = (ye - local_y) + best_y;

            Xads = [Xads, def_global_x]; %#ok<AGROW>
            Yads = [Yads, def_global_y]; %#ok<AGROW>

            if DistMode == 1
                t_ads = Sub_GeneratePowerLawWithMean(TI, tm_ads, 1);
            elseif DistMode == 2
                t_ads = Sub_GenerateExponentialWithMean(tm_ads, 1);
            else
                t_ads = Sub_GenerateUniformWithMean(tm_ads, 2 * tm_ads, 1);
            end
            
            % 防止因无穷均值(如 TI=-1.5)导致的负数时间，引发内存爆库死循环
            if isnan(t_ads) || t_ads < 0
                t_ads = tjmp; 
            end
            
            Tads_list = [Tads_list, t_ads]; % 记录单次真实的微观吸附时间

            tclock = tclock + t_ads + tjmp;
        else
            tclock = tclock + tjmp;
        end

        xb = xe;
        yb = ye;

        if tclock >= t_tot
            t_r = tclock - t_tot;
            if t_r < 0.0, t_r = 0.0; end
            break;
        end
    end

    if isempty(Xads)
        Xads = NaN;
        Yads = NaN;
        Tads_list = NaN; 
    end
end