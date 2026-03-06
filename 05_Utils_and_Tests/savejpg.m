%% 批量转换fig为WPS兼容的JPG（递归扫描+跳过已存在+权限修复）
% 解决问题：Matlab生成的JPG无法被WPS导入识别，复制粘贴却可行的兼容问题
% 使用说明：仅需修改rootFolder为你的目标文件夹路径

% ===================== 核心参数配置（仅改这里！）=====================
rootFolder = fullfile('D:\Ling_San\Documents\科研\力学\数据\260116 滑移距离 ds = 0.05k jf =1e8'); % 替换为你的文件夹路径
imgQuality = 100;  % JPG质量（100=无损，兼容WPS最佳）
% ===================== 全局变量初始化 =====================
global GLOBAL_FIG_FILES GLOBAL_FOLDER_COUNT;
GLOBAL_FIG_FILES = {};   % 存储所有fig文件路径
GLOBAL_FOLDER_COUNT = 0; % 扫描的文件夹总数

% ===================== 第一步：取消文件夹只读权限 =====================
disp('【步骤1/3】正在取消文件夹及子文件只读属性...');
if ispc()  
    try
        cmd = ['attrib -r "', rootFolder, '\*.*" /s /d'];
        [status, ~] = system(cmd);
        % 修复：替换三元运算符为if-else（兼容所有MATLAB版本）
        if status == 0
            disp('✅ Windows：只读属性取消成功！');
        else
            disp('⚠️ Windows：权限修改可能不完整');
        end
    catch
        disp('❌ Windows：权限修改失败（不影响转换，仅可能无法覆盖文件）');
    end
else
    disp('⚠️ 非Windows系统，跳过权限修改');
end
disp('----------------------------------------');

% ===================== 第二步：递归扫描所有fig文件 =====================
disp('【步骤2/3】正在递归扫描所有文件夹中的fig文件...');
recursiveFindFig(rootFolder);
totalFig = length(GLOBAL_FIG_FILES);
scannedFolder = GLOBAL_FOLDER_COUNT;

if totalFig == 0
    disp(['⚠️ 扫描完成：共扫描', num2str(scannedFolder), '个文件夹，未找到fig文件！']);
    return;
end
disp(['✅ 扫描完成：共扫描', num2str(scannedFolder), '个文件夹，找到', num2str(totalFig), '个fig文件']);
disp('----------------------------------------');

% ===================== 第三步：批量转换为WPS兼容的JPG =====================
disp('【步骤3/3】开始转换为WPS兼容的JPG（getframe+imwrite方案）...');
successNum = 0; failNum = 0; skipNum = 0;
failList = {}; skipList = {};

for idx = 1:totalFig
    figPath = GLOBAL_FIG_FILES{idx};
    [fileDir, fileName, ~] = fileparts(figPath);
    jpgPath = fullfile(fileDir, [fileName, '.jpg']); % 强制小写扩展名
    
    % 进度提示
    progress = idx/totalFig*100;
    disp(['进度：', sprintf('%.1f%%', progress), ' (', num2str(idx), '/', num2str(totalFig), ')']);
    disp(['处理文件：', figPath]);
    
    % 跳过已存在的JPG
    if exist(jpgPath, 'file') == 2
        skipNum = skipNum + 1;
        skipList{end+1} = figPath;
        disp(['⏩ 跳过：已存在同名JPG（', jpgPath, '）']);
        disp('----------------------------------------');
        continue;
    end
    
    % 核心转换逻辑（兼容WPS）
    try
        % 打开fig并隐藏窗口
        figHandle = openfig(figPath, 'invisible');
        set(figHandle, 'Visible', 'off');
        
        % 关键：提取图像像素数据（避开print的格式兼容问题）
        frame = getframe(figHandle);  % 获取窗口像素数据
        imgData = frame.cdata;        % RGB像素矩阵
        
        % 生成标准化JPG（WPS 100%识别）
        imwrite(imgData, jpgPath, 'Quality', imgQuality);
        
        % 清理资源
        close(figHandle);
        successNum = successNum + 1;
        disp(['✅ 转换成功：', fileName, '.fig → ', fileName, '.jpg']);
    catch ME
        failNum = failNum + 1;
        failList{end+1} = {figPath, ME.message};
        disp(['❌ 转换失败：', fileName, '.fig']);
        disp(['   原因：', ME.message]);
        % 确保关闭fig句柄
        if exist('figHandle', 'var') && ishandle(figHandle)
            close(figHandle);
        end
    end
    disp('----------------------------------------');
end

% ===================== 转换完成统计报告 =====================
disp('📊 转换任务全部完成！最终统计：');
disp(['   总扫描文件夹数：', num2str(scannedFolder)]);
disp(['   总扫描fig文件数：', num2str(totalFig)]);
disp(['   ✅ 成功转换数：', num2str(successNum)]);
disp(['   ❌ 转换失败数：', num2str(failNum)]);
disp(['   ⏩ 跳过数（已有JPG）：', num2str(skipNum)]);

if failNum > 0
    disp('❌ 失败文件清单：');
    for k = 1:length(failList)
        disp(['   文件：', failList{k}{1}]);
        disp(['   原因：', failList{k}{2}]);
        disp('   ---');
    end
end
if skipNum > 0
    disp('⏩ 跳过文件清单：');
    for k = 1:length(skipList)
        disp(['   ', skipList{k}]);
    end
end

% ===================== 递归扫描fig文件的函数 =====================
function recursiveFindFig(currentFolder)
    global GLOBAL_FIG_FILES GLOBAL_FOLDER_COUNT;
    GLOBAL_FOLDER_COUNT = GLOBAL_FOLDER_COUNT + 1;
    disp(['扫描文件夹：', currentFolder]);
    
    % 获取当前文件夹所有项
    allItems = dir(currentFolder);
    for i = 1:length(allItems)
        itemName = allItems(i).name;
        if strcmp(itemName, '.') || strcmp(itemName, '..')
            continue;
        end
        fullPath = fullfile(currentFolder, itemName);
        
        % 递归扫描子文件夹
        if allItems(i).isdir
            recursiveFindFig(fullPath);
        % 收集.fig/.FIG文件（不区分大小写）
        else
            [~, ~, ext] = fileparts(fullPath);
            if strcmpi(ext, '.fig')
                GLOBAL_FIG_FILES{end+1} = fullPath;
                disp(['   找到fig：', fullPath]);
            end
        end
    end
end