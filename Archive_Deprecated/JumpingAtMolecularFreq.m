% Sub_JumpingAtMolecularFreq()
% Generating N trajectories at molecular jumping frequency
%  
% Last modified 03/12/2025
clear
clc
close all

Date = date;

NN = 1;                     % Number of trajectory
t_total = 10;                % Total time for the each trajectory
jf = 10^(10);               % Jumping frequency: Hz
Ts = [0.02];                % Sampling time of camera
AdRR = 1;
adR = 1*AdRR;       % Adsorption radius: nm
tmads = [0.09 0.09 0.09 0.1 0.3 0.5 0.8 1.0 ];               % Mean adsoption time before the next relocation: s
ds = [20] ;            % Inter-defect distance: nm
% Xshiftvelocity = [40 80 160 320 480 640 800 1000];     % Shift Velocity in x axis : nm/s
Xshiftvelocity = [0];
Yshiftvelocity = zeros(length(Xshiftvelocity));        % Shift Velocity in y axis : nm/s 

DistributionMode = 2;

switch DistributionMode
    case 1
        TimeIndex = [2.5]; % Power law time paramaters of adsorption time 
    case 2
        TimeIndex = tmads; % Exponential Law time paramaters of adsorption time : Timeindex = meanvalue > 0 , λ = 1/meanValue;
    case 3
        TimeIndex = tmads;
end

%{
Mode = 1 Sub_GeneratePowerLawWithMean(Timeindex, tm_ads, 1);
Mode = 2 Sub_GenerateExponentialWithMean(Timeindex, 1);
Mode = 3 range = [Timeindex]; %The interval length corresponding to uniform distribution
         t_ads = Sub_GenerateUniformWithMean(Timeindex, range, 1);  
%}

Mnt = 0;

D = 10^(-8);      % Theoretical diffusion coefficient
fontsize=14;

L_total = 100*10^(-6)* 1e9;      % total size for a square to be consider: nm

%% The trajectory at the molecular jumping frequency


% cmap = hsv(N); % Creates a np-by-3 set of colors from the HSV colormap



% Initial position of each trajectory

x0 = 1*10^(-6)*rand(1,1)+50*10^(-6);
y0 = 1*10^(-6)*rand(1,1)+50*10^(-6);
x0 = x0 * 1e9 ;   % nm
y0 = y0 * 1e9 ;   % nm


%%

N = length(TimeIndex);
M = length(Xshiftvelocity);
Mean = length(tmads);
TL = length(Ts);
DS = length(ds);

if Mnt == 1
    figure
end


% for len = 0 : 4 
len = 0;

for ti = 1 : N
for dss = 1 :  DS   
    for tl = 1 : TL
    for mean=1:Mean
        for q=1:M
            close all
            prev_time = now();
            Timeindex = TimeIndex(ti);
            tm_ads = tmads(mean);
            % Ts = Tss(i);
            % Molecular jumping distance 
            tau = 1/jf;             % JUMPING interval in seconds
            k = sqrt(2*D*tau) * 10^9 ;
            sprintf('The molecular jumping distance is %1.1f nm', k)
        
            
            % Defect localization
            Ndefect = round(L_total/ds(dss));
            Xd = rand(Ndefect^2,1) * L_total;
            Yd = rand(Ndefect^2,1) * L_total;
            XYd = [Xd Yd];
        
            X = [];     % to record the adsorption location 
            Y = [];     % to record the adsorption location
            Frame = []; % to record the frame number
            t_r =0;     % Subsequent adsorption time in the beginning of the frame to be checked
            
            xshiftvelocity = Xshiftvelocity(q);
            yshiftvelocity = Yshiftvelocity(q);
    
            if Mnt == 1
                figure(1),hold on
                figure(2),hold on
            end
                     
            for j=1:round(t_total/Ts(tl))
                t = now * 86400;
                if j<3
                    Fig = 1;
                    figure(2)
                else
                    Fig = 2;
                end
                t_a = t_r;
                DataTrans = [Ts(tl),Timeindex,t_a,tm_ads,k,jf,adR,Fig,j, xshiftvelocity, yshiftvelocity];
                [xe,ye,Xads,Yads,t_r] = Sub_JumpingBetweenEachFrame(x0,y0,XYd,DataTrans,DistributionMode,len);
                x0 = xe;
                y0 = ye;
                X = [X;Xads'];
                Y = [Y;Yads'];
                f = ones(size(Yads'))*j;
                Frame = [Frame;f];
                tmp1 = round(j/(t_total/Ts(tl))*100,6);
                seconds2remainingtime(prev_time,tmp1,1);

                if Mnt == 1
                    figure(3)
                    set(gcf,"Position",[1000 400 560 420])
                    hold on
                    if ~isempty(Xads)
                        s = scatter(Xads*1E6,Yads*1E6,'MarkerEdgeColor',[0 0.45 0.74],...
                          'MarkerFaceColor',[0 0.45 0.74],'SizeData',40);
                        alpha(s,.5)
                        xlabel('X (\mum)');ylabel('Y (\mum)');
                        box on
                    end
                end
        
                if Mnt == 1
                    if mod(j,20)==0
                        figure(2)
                        close figure 2
                    end
            
                    if mod(j,200)==0
                        figure(3)
                        close figure 3
                    end
                end
       
        
            end
        
        
        
        [m,n] = find(isnan(X));
        X(m) = []; Y(m) = []; Frame(m) = []; 
        
        %
        
        clear positionlist;
        positionlist(:,1) = X;      % In nm
        positionlist(:,2) = Y;      % In nm
        positionlist(:,3) = Frame;
        
        %
        DTRACK = 1000;                      % The maximum tracking length: nm
        
        FigN = 3;
        DataTrans = [Ts(tl),Timeindex,t_a,tm_ads,k,jf,adR,Fig,j, xshiftvelocity, yshiftvelocity];
        [SD,DX,DY,DL] = Sub_TrajectoryAnalysis(positionlist,DTRACK,FigN,Ts(tl),DataTrans);
        
        % FN = strcat('2DDs',num2str(ds(i)*10^9),'nmAdR0p5nmTtot',num2str(t_total),'sTadspt',num2str(tm_ads),'s.mat')
        % FN = strcat('2DDs170nmAdR0p5nmTtot1000sTadspt0.03sObervationWindow',num2str(Ts(tl)),'s.mat')
        FN = strcat('test',num2str(Timeindex),'.mat')
        
        % save(FN)
        
        if Mnt == 1    
            figure(10)
            plot(X,Y,'.-','MarkerSize',20)
        end
        
        end
    end
end
end
end
% end
system('shutdown -s');
% 
% 
% %% To show the simulations
% clear
% clc
% 
% FN = '2DDs40nmAdR0p5nmTtot1000sTadspt0.04s.mat';
% DTRACK =1000;
% FigN =20;
% 
% To plot the probability of dx/dy
% Sub_ShowProbabilityDXDY(FN,DTRACK,FigN)
% 
% 
% % end
% %% To plot the trajectory
% 
% clear
% clc
% 
% FN = '2DDefectEffectDs10nmTtot100sAdR0p5nm.mat';
% SamplingRatio = 10;  % To show one trajectory every 'SamplingRatio' trajectories
% FigN =30;
% SizeC = 2;          % min size of  trajectories to be plotted
% 
% Sub_ShowTrajectory(FN,SamplingRatio,FigN,SizeC)
% 









