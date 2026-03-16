function JumpingAtMolecularFreq()
% High-performance Brownian dynamics driver with binary hash-table sharing.

clc; close all;
clear persistent;
killall();

global RAM_History baseRAM;
RAM_History = [];
if ispc
    [userMem, ~] = memory;
    baseRAM = userMem.MemUsedMATLAB / 1048576;
else
    baseRAM = 0;
end

fprintf('>>> [%s] Initializing parallel environment...\n', datestr(now, 'HH:MM:SS'));

try
    poolObj = gcp('nocreate');
    if ~isempty(poolObj)
        delete(poolObj);
    end
catch
end

PerfTestMode = true;

startTime = tic;
startTimeStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');

TimeSeed = 315231049;
t_total = 1000;
D = 1e-10;
L_total = 100 * 1e3;

jf_list = [1e8];
adR_list = [1.0];
ds_list = [10, 20, 40, 60, 80, 100];

Repeats = 1:1;
DistributionModes = [1, 2, 3];
TimeIndex_list = [-2.5, 2.5];
Ts_list = [0.02];
tmads_list = [0.04];
Vx_ratio_list = [0, 1e-6, 1e-5];
Vy_ratio_list = [0];

if ispc
    timer_cmd = ['global RAM_History baseRAM; ', ...
        'try, [uMem, ~] = memory; ', ...
        'RAM_History = [RAM_History, max(0, (uMem.MemUsedMATLAB / 1048576) - baseRAM)]; ', ...
        'catch, end'];
    memProfiler = timer('ExecutionMode', 'fixedRate', 'Period', 2.0, ...
        'TimerFcn', timer_cmd);
    start(memProfiler);
end

fprintf('>>> [%s] Building static hash tables on disk...\n', datestr(now, 'HH:MM:SS'));
L_block = 10000;
cell_size = 100;
nx = ceil(L_block / cell_size);
ny = ceil(L_block / cell_size);
max_pts_per_nbhd = 150;
InitPositions = zeros(max(Repeats), 2);

for Rep = Repeats
    rng(Rep + TimeSeed, 'twister');
    InitPositions(Rep, :) = (1e-6 * rand(1, 2) + 50e-6) * 1e9;

    for adR_val = adR_list
        for ds_val = ds_list
            rng(Rep + TimeSeed, 'twister');
            Ndefect_block = round(L_block / ds_val);
            valid_L = L_block - 2 * adR_val;

            Map1 = rand(Ndefect_block^2, 2) * valid_L + adR_val;
            Map2 = [Map1(:, 2), L_block - Map1(:, 1)];
            Map3 = [L_block - Map1(:, 1), L_block - Map1(:, 2)];
            Map4 = [L_block - Map1(:, 2), Map1(:, 1)];
            Maps = {Map1, Map2, Map3, Map4};

            HashX = zeros(max_pts_per_nbhd, nx, ny, 4, 'double');
            HashY = zeros(max_pts_per_nbhd, nx, ny, 4, 'double');
            HashCount = zeros(nx, ny, 4, 'double');

            for MapIdx = 1:4
                Xd = Maps{MapIdx}(:, 1);
                Yd = Maps{MapIdx}(:, 2);

                for ix = 1:nx
                    for iy = 1:ny
                        x_min = (ix - 2) * cell_size;
                        x_max = (ix + 1) * cell_size;
                        y_min = (iy - 2) * cell_size;
                        y_max = (iy + 1) * cell_size;

                        idx = find(Xd >= x_min & Xd < x_max & Yd >= y_min & Yd < y_max);
                        count = length(idx);

                        if count > max_pts_per_nbhd
                            count = max_pts_per_nbhd;
                            idx = idx(1:max_pts_per_nbhd);
                        end

                        HashCount(ix, iy, MapIdx) = count;
                        if count > 0
                            HashX(1:count, ix, iy, MapIdx) = Xd(idx);
                            HashY(1:count, ix, iy, MapIdx) = Yd(idx);
                        end
                    end
                end
            end

            binFileName = sprintf('SharedHash_Rep%d_ds%g_adR%g.bin', Rep, ds_val, adR_val);
            fid = fopen(binFileName, 'w');
            fwrite(fid, HashX(:), 'double');
            fwrite(fid, HashY(:), 'double');
            fwrite(fid, HashCount(:), 'double');
            fclose(fid);
        end
    end
end
cleanupObj = onCleanup(@() cleanup_hash_files());

Tasks = [];
for Rep = Repeats
    x0 = InitPositions(Rep, 1);
    y0 = InitPositions(Rep, 2);
    for DistMode = DistributionModes
        for Ts = Ts_list
            for tm_ads = tmads_list
                for TI = TimeIndex_list
                    for jf = jf_list
                        for adR = adR_list
                            for ds = ds_list
                                for vx_ratio = Vx_ratio_list
                                    for vy_ratio = Vy_ratio_list
                                        Tasks = [Tasks; Ts, tm_ads, TI, vx_ratio, vy_ratio, DistMode, Rep, x0, y0, jf, adR, ds]; %#ok<AGROW>
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

TotalTasks = size(Tasks, 1);
if TotalTasks == 0
    error('Task generation failed.');
end

Tasks = Tasks(randperm(TotalTasks), :);

MaxPhysicalCores = feature('numcores');
NumCores = min(TotalTasks, max(1, MaxPhysicalCores - 2));
fprintf('>>> [%s] Total tasks: %d | Workers: %d\n', datestr(now, 'HH:MM:SS'), TotalTasks, NumCores);

pool = gcp('nocreate');
if isempty(pool) || pool.NumWorkers ~= NumCores
    if ~isempty(pool)
        delete(pool);
    end
    pool = parpool('local', NumCores);
end

setappdata(0, 'taskProg', zeros(1, TotalTasks));
setappdata(0, 'lastMsgLen', 0);
dq = parallel.pool.DataQueue;
afterEach(dq, @(data) update_progress_console(data, TotalTasks, startTime));
futures = parallel.FevalFuture.empty(TotalTasks, 0);

fprintf('>>> [%s] Dispatching tasks...\n', datestr(now, 'HH:MM:SS'));
fprintf('------------------------------------------------------------\n');

for i = 1:TotalTasks
    futures(i) = parfeval(pool, @Worker_JumpingTask, 1, i, dq, Tasks(i, :), t_total, D, TimeSeed, nx, ny, max_pts_per_nbhd);
end

baseResultDir = 'Simulation_Results';
if ~exist(baseResultDir, 'dir')
    mkdir(baseResultDir);
end
runID = datestr(now, 'yyyymmdd_HHMMSS');
mainRunDir = fullfile(baseResultDir, ['Task_' runID]);
if ~exist(mainRunDir, 'dir')
    mkdir(mainRunDir);
end
DistNames = {'PowerLaw', 'Exp', 'Uniform'};

fprintf('>>> Output directory: %s\n', mainRunDir);

for i = 1:TotalTasks
    [idx, res] = fetchNext(futures);
    p = Tasks(idx, :);

    curr_Ts = p(1);
    curr_tmads = p(2);
    curr_TI = p(3);
    curr_vx_ratio = p(4);
    curr_vy_ratio = p(5);
    curr_DistMode = p(6);
    curr_Rep = p(7);
    curr_jf = p(10);
    curr_adR = p(11);
    curr_ds = p(12);

    if isfield(res, 'pos') && ~isempty(res.pos)
        pos = res.pos;
        valid_idx = ~isnan(pos(:, 1));
        positionlist = pos(valid_idx, :);

        if size(positionlist, 1) > 2
            DTRACK = 1000;
            FigN = 0;
            current_k = res.k;
            curr_vx = curr_vx_ratio * current_k;
            curr_vy = curr_vy_ratio * current_k;
            DataTrans_Analysis = [curr_Ts, curr_TI, res.t_r, curr_tmads, current_k, curr_jf, curr_adR, FigN, 0, curr_vx, curr_vy];

            try
                cDist = DistNames{curr_DistMode};
                subdirName = sprintf('Rep%d_%s_TI%.1f_Tads%.4f_DS%g_adR%g_jf%1.0e_ratio_%gk', ...
                    curr_Rep, cDist, curr_TI, curr_tmads, curr_ds, curr_adR, curr_jf, curr_vx_ratio);
                subDirPath = fullfile(mainRunDir, subdirName);
                if ~exist(subDirPath, 'dir')
                    mkdir(subDirPath);
                end

                filePrefix = subdirName;
                if PerfTestMode
                    matFilePath = fullfile(subDirPath, [filePrefix, '_Fast_NoPlot.mat']);
                    save(matFilePath, 'positionlist', 'p', 'res', '-v7.3');
                else
                    [SD, DX, DY, DL, analysis_results] = Sub_TrajectoryAnalysis(positionlist, DTRACK, FigN, curr_Ts, DataTrans_Analysis, subDirPath, filePrefix); %#ok<NASGU,ASGLU>
                    matFilePath = fullfile(subDirPath, [filePrefix, '.mat']);
                    save(matFilePath, 'positionlist', 'SD', 'DX', 'DY', 'DL', 'p', 'res', 'analysis_results', '-v7.3');
                end

                fprintf('\n[OK] Task %d/%d -> %s\n', idx, TotalTasks, subdirName);
            catch ME
                fprintf('\n[ERROR] Task %d failed: %s\n', idx, ME.message);
            end
        else
            fprintf('\n[SKIP] Task %d: too few trajectory points.\n', idx);
        end
    else
        fprintf('\n[SKIP] Task %d: empty worker result.\n', idx);
    end

    setappdata(0, 'lastMsgLen', 0);
    clear res pos positionlist SD DX DY DL analysis_results;
    if mod(i, 10) == 0
        drawnow;
    end
end
fprintf('\n');

if ispc && exist('memProfiler', 'var') && isvalid(memProfiler)
    stop(memProfiler);
    if ~isempty(RAM_History)
        avgNetRAM = mean(RAM_History);
        peakNetRAM = max(RAM_History);
    else
        avgNetRAM = 0;
        peakNetRAM = 0;
    end
    delete(memProfiler);
else
    avgNetRAM = 0;
    peakNetRAM = 0;
end

endTimeStr = datestr(now, 'yyyy-mm-dd HH:MM:SS');
totalDuration = toc(startTime);

binFiles = dir('SharedHash_*.bin');
if ~isempty(binFiles)
    payloadSizeMB = sum([binFiles.bytes]) / 1048576;
else
    payloadSizeMB = 0;
end
allVars = whos;
totalWorkspaceMB = sum([allVars.bytes]) / 1048576;

logDir = 'Experiment_Logs';
if ~exist(logDir, 'dir')
    mkdir(logDir);
end
logFileName = sprintf('SimLog_%s.txt', runID);
logFilePath = fullfile(logDir, logFileName);
fid = fopen(logFilePath, 'w');
fprintf(fid, '============================================================\n');
fprintf(fid, 'Brownian dynamics experiment report\n');
fprintf(fid, '============================================================\n');
fprintf(fid, 'Run ID                      : %s\n', runID);
fprintf(fid, 'Workers                     : %d\n', NumCores);
fprintf(fid, 'Start time                  : %s\n', startTimeStr);
fprintf(fid, 'End time                    : %s\n', endTimeStr);
fprintf(fid, 'Duration                    : %.2f min\n', totalDuration / 60);
fprintf(fid, 'Completed tasks             : %d\n', TotalTasks);
fprintf(fid, 'Output path                 : %s\n', fullfile(pwd, mainRunDir));
fprintf(fid, 'Hash payload                : %.2f MB\n', payloadSizeMB);
fprintf(fid, 'Workspace size              : %.2f MB\n', totalWorkspaceMB);
if ispc
    fprintf(fid, 'MATLAB base RAM             : %.2f MB\n', baseRAM);
    fprintf(fid, 'Average net RAM             : %.2f MB\n', avgNetRAM);
    fprintf(fid, 'Peak net RAM                : %.2f MB\n', peakNetRAM);
end
fclose(fid);

rmappdata(0, 'taskProg');
rmappdata(0, 'lastMsgLen');

warning('off', 'all');
delete(pool);
try
    myCluster = parcluster('Processes');
    delete(myCluster.Jobs);
catch
    try
        myCluster = parcluster('local');
        delete(myCluster.Jobs);
    catch
    end
end
warning('on', 'all');

cleanup_hash_files();
clear global RAM_History baseRAM;
fprintf('>>> Cleanup complete.\n');

end

function out = Worker_JumpingTask(taskID, dq, p, t_tot, D, TimeSeed, nx, ny, max_pts)
Ts = p(1);
tm_ads = p(2);
TI = p(3);
vx_ratio = p(4);
vy_ratio = p(5);
DistMode = p(6);
Rep = p(7);
x0 = p(8);
y0 = p(9);
jf = p(10);
adR = p(11);
ds = p(12);

tau = 1 / jf;
k = sqrt(2);
vx = vx_ratio * k;
vy = vy_ratio * k;

binFileName = sprintf('SharedHash_Rep%d_ds%g_adR%g.bin', Rep, ds, adR);
m = memmapfile(binFileName, 'Format', { ...
    'double', [max_pts, nx, ny, 4], 'HashX'; ...
    'double', [max_pts, nx, ny, 4], 'HashY'; ...
    'double', [nx, ny, 4], 'HashCount'}, 'Writable', false);

HashX = m.Data(1).HashX;
HashY = m.Data(1).HashY;
HashCount = m.Data(1).HashCount;

cx = x0;
cy = y0;
tr = 0;
nf = round(t_tot / Ts);
report_step = max(1, round(nf / 20));

chunk = 5000000;
X_buf = zeros(chunk, 1, 'double');
Y_buf = zeros(chunk, 1, 'double');
F_buf = zeros(chunk, 1, 'uint32');
cursor = 0;

for j = 1:nf
    args = [Ts, TI, tr, tm_ads, k, jf, adR, 0, j, vx, vy, DistMode];
    [xe, ye, Xa, Ya, tr] = Sub_JumpingBetweenEachFrame_mex_mex(cx, cy, HashX, HashY, HashCount, args, TimeSeed);
    cx = xe;
    cy = ye;

    if ~isnan(Xa(1))
        nNew = length(Xa);
        if cursor + nNew > length(X_buf)
            new_size = length(X_buf) + chunk;
            X_buf(new_size, 1) = 0;
            Y_buf(new_size, 1) = 0;
            F_buf(new_size, 1) = 0;
        end
        X_buf(cursor + 1:cursor + nNew) = Xa';
        Y_buf(cursor + 1:cursor + nNew) = Ya';
        F_buf(cursor + 1:cursor + nNew) = uint32(j);
        cursor = cursor + nNew;
    end

    if mod(j, report_step) == 0
        send(dq, [taskID, j / nf]);
    end
end

pause(0.1 + 1.9 * rand());
send(dq, [taskID, 1.0]);
out.pos = [X_buf(1:cursor), Y_buf(1:cursor), double(F_buf(1:cursor))];
out.t_r = tr;
out.k = k;

clear m HashX HashY HashCount;
end

function update_progress_console(data, total, startTime)
prog = getappdata(0, 'taskProg');
prog(data(1)) = data(2);
setappdata(0, 'taskProg', prog);
len = getappdata(0, 'lastMsgLen');

if isempty(len) || len == 0
    fprintf('\n');
else
    fprintf(repmat('\b', 1, len));
end

delta = sum(prog) / total;
elap = toc(startTime);
doneCount = sum(prog == 1.0);
activeNodes = sum(prog > 0 & prog < 1.0);

if delta > 0
    remTime = elap * (1 - delta) / delta;
    etaStr = sprintf('%02d:%02d:%02d', floor(remTime / 3600), floor(mod(remTime, 3600) / 60), floor(mod(remTime, 60)));
else
    etaStr = '--:--:--';
end

barLen = 20;
filled = floor(delta * barLen);
bar = [repmat('>', 1, filled), repmat(' ', 1, barLen - filled)];
msg = sprintf('Progress: [%s] %5.1f%% | Done: %d/%d | Active: %d | ETA: %s', bar, delta * 100, doneCount, total, activeNodes, etaStr);
fprintf('%s', msg);
setappdata(0, 'lastMsgLen', length(msg));
end

function cleanup_hash_files()
files = dir('SharedHash_*.bin');
for k = 1:numel(files)
    try
        delete(files(k).name);
    catch
    end
end
end
