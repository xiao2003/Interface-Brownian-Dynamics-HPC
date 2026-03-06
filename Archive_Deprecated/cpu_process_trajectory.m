% ----------------------CPU并行处理函数----------------------
function [flag] = cpu_process_trajectory(midx, ti, dss, tl, ...
                        TimeIndex, tmads, Ts, ds, t_total, jf, D, ...
                        L_total, Xshiftvelocity, Yshiftvelocity, ...
                        DistributionMode, Mnt, adR)
                    flag = 0;
                    % 预先计算常量以避免重复计算
                    tau = 1 / jf;
                    k = sqrt(2 * D * tau) * 1e9;  % 分子跳跃距离(nm)
                    % 初始化位置（每个并行实例独立初始化）- 使用向量化初始化
                    xy0 = (1e-6 * rand(1, 2) + [50e-6, 50e-6]) * 1e9;  % 转换为nm
                    x0 = xy0(1);
                    y0 = xy0(2); 
                    for q = 1:length(Xshiftvelocity)
                        prev_time = now();
                        Timeindex = TimeIndex(ti);
                        tm_ads = tmads;  % 使用正确的变量名
                        
                        % 生成缺陷位置 - 使用向量化方式
                        Ndefect = round(L_total / ds(dss));
                        defect_coords = rand(Ndefect^2, 2) * L_total;
                        XYd = defect_coords;
                        
                        % 预先分配存储空间以提高效率
                        total_frames = round(t_total / Ts(tl));
                        max_expected_points = total_frames * 10; % 预估最大点数
                        X = zeros(max_expected_points, 1);
                        Y = zeros(max_expected_points, 1);
                        Frame = zeros(max_expected_points, 1);
                        current_idx = 1;
                        t_r = 0;  % 初始吸附时间
                        
                        xshiftvelocity_val = Xshiftvelocity(q);
                        yshiftvelocity_val = Yshiftvelocity(q);
                        ts_val = Ts(tl);
                        timeindex_val = Timeindex;
                        tm_ads_val = tm_ads;
                        adR_val = adR;
                        Mnt_val = Mnt;
                        DistributionMode_val = DistributionMode;
                        frame_count = total_frames;
                        modfram_count = 0.05*frame_count;
                        jf_val = jf;
                        D_val = D;
                        L_total_val = L_total;
                        ds_val = ds(dss);
                        dss_val = dss;
                        tl_val = tl;
                        ti_val = ti;
                        midx_val = midx;  % 使用不同的变量名
                        q_val = q;
                        t_total_val = t_total;
                        k_val = k;
                        tau_val = tau;
                        XYd_val = XYd;
                        

                        % folder_name = sprintf('cpu_tmp_ti%d_dss%d_m%d_q%d.mat', ti_val, dss_val, midx_val, q_val);
                        % if ~exist(folder_name, 'dir')
                        %     mkdir(folder_name);
                        % end

                        % 帧循环（核心计算）- 向量化优化
                        for j = 1:frame_count
                            t_a = t_r;
                            DataTrans = [ts_val, timeindex_val, t_a, tm_ads_val, k_val, jf_val, adR_val, ...
                                double(Mnt_val), j, xshiftvelocity_val, yshiftvelocity_val,DistributionMode_val];
                            % 调用子函数计算帧内轨迹
                            [xe, ye, Xads, Yads, t_r] = Sub_JumpingBetweenEachFrame(...
                                x0, y0, XYd_val, DataTrans);
                            x0 = xe;
                            y0 = ye;
                            
                            % 批量存储轨迹数据以减少索引操作
                            num_points = length(Xads);
                            if current_idx + num_points - 1 <= length(X)
                                X(current_idx:current_idx+num_points-1) = Xads';
                                Y(current_idx:current_idx+num_points-1) = Yads';
                                Frame(current_idx:current_idx+num_points-1) = j;
                                current_idx = current_idx + num_points;
                            else
                                % 扩展数组大小
                                X = [X; zeros(num_points, 1)];
                                Y = [Y; zeros(num_points, 1)];
                                Frame = [Frame; j*ones(num_points, 1)];
                                X(current_idx:current_idx+num_points-1) = Xads';
                                Y(current_idx:current_idx+num_points-1) = Yads';
                                Frame(current_idx:current_idx+num_points-1) = j;
                                current_idx = current_idx + num_points;
                            end

                            tmp1 = round(j / frame_count * 100, 6);
                            seconds2remainingtime(prev_time, tmp1, 1);
                            % if mod(j,modfram_count) == 0 || j == frame_count
                            %     tmpX = X';
                            %     tmpY = Y';
                            %     tmpFrame = Frame;
                            %     FN = fullfile(folder_name, sprintf('process%.3f_cpu_tmp_ti%d_dss%d_m%d=%.3f_q%d.mat', tmp1, ti_val, dss_val, midx_val,tm_ads_val, q_val));
                            %     save(FN, 'tmpX', 'tmpY', 'tmpFrame');                
                            % end
                        end
                        
                        % 截断未使用的数组部分
                        X = X(1:current_idx-1);
                        Y = Y(1:current_idx-1);
                        Frame = Frame(1:current_idx-1);
                        
                        % 数据清洗 - 向量化处理NaN值
                        nan_indices = isnan(X) | isnan(Y);
                        X(nan_indices) = [];
                        Y(nan_indices) = [];
                        Frame(nan_indices) = [];
                        
                        % 轨迹分析
                        length_X = length(X);
                        if length_X > 0
                            positionlist = zeros(length_X, 3);
                            positionlist(:, 1) = X;
                            positionlist(:, 2) = Y;
                            positionlist(:, 3) = Frame;
                            DTRACK = 1000;  % 最大跟踪长度(nm)
                            Sub_TrajectoryAnalysis(positionlist, DTRACK, 4*(midx_val-1)+1, ts_val, DataTrans);
                        end
                    end
end