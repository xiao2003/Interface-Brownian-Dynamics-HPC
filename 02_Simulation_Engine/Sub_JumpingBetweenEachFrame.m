function [xe,ye,Xads,Yads,t_r] = Sub_JumpingBetweenEachFrame(x0,y0,XYd,DataTrans,DistributionMode)
% To simulate the molucular travelling between each frame

% x0: initial position
% y0: initial position
% t_tot: time interval between each frame or the total simulation time here
% tm_ads: mean adsorption time on each defect
% k: molecular jumping distance at a given diffusion coefficient
% jf: jumping frequency
% XYd in m: defect coordination
% adR in m: adsorption radius

% xe: x position at the end of the simulation, that will be the start
% position in the next simulation
% ye: y position at the end fo the simulation, that will be the start
% position in the next simulation

Mnt = 0;        % Monitoring the simulation: On (Mnt=1) ; Off(Mnt=0)
LmaxJUMP = 8000;           % The maximum jumping distance between ajacent two frames : nm

t_tot = DataTrans(1);      % time interval between each frame or the total simulation time here (Sampling time of camera)
Timeindex = DataTrans(2);  % Time parameters of adsorption time
t_a = DataTrans(3);        % Subsequent adsorption time due to the adsorption event from the last frame
tm_ads = DataTrans(4);     % Mean adsoption time before the next relocation: s
k = DataTrans(5);          % Molecular jumping distance at a given diffusion coefficient
jf = DataTrans(6);         % Jumping frequency
adR = DataTrans(7);        % Adsorption radius
Fig = DataTrans(8);        % Figure Number
jj = DataTrans(9);         % The jjth frame   
xshiftvelocity = DataTrans(10);    % Shift Velocity in x axis : nm/s
yshiftvelocity = DataTrans(11);    % Shift Velocity in y axis : nm/s

dx = [];
dy = [];
x = [];
y = [];

Xd = XYd(:,1);
Yd = XYd(:,2);



% To prepare the defect map next to the jumping


[m1,n1] = find(((x0 - Xd).^2+(y0 - Yd).^2)<(LmaxJUMP)^2);
XdN = Xd(m1); YdN = Yd(m1); %  coordination of neighbour defects

if Mnt == 1             % Monitoring
    figure(Fig)
    hold on
    viscircles([XdN YdN],adR,'Color','r');
    box on
    xlabel('X (m)');ylabel('Y (m)')
    axis([x0(1)-LmaxJUMP/5 x0(1)+LmaxJUMP/5 y0(1)-LmaxJUMP/5 y0(1)+LmaxJUMP/5])
    pause(0.001)
end

% 
% figure(Fig)
% axis equal
% plot(x0,y0,'*c')
% plot(Xd(n),Yd(n),'xc','MarkerSize',20)
% legend('Initial Position of ions','Nearest defect')
% title(strcat(num2str(LmaxJUMP/5*10^(9)), 'nm\times', num2str(LmaxJUMP/5*10^(9)),'nm'))

% The following generates Gaussian distribution

Ln = t_tot*jf;     % the maximum possible trajectory length in the simulation
tjmp = 1/jf;        % molecular jumping time


j=1;
tclock = t_a;       % Subsequent adsorption time due to the adsorption event from the last frame
xe = x0;
ye = y0;
Xads = [];
Yads = [];
xb = x0;
yb = y0;
t_ads = 0;

if Mnt == 1         % Monitoring
    if Fig==1       % To record the jumping at molecular frequency
        v = VideoWriter("ProtonJumpingsAtInterfaces.avi");
        open(v)
    end
end


if tclock<t_tot
    % Xads(1) = xe; Yads(1) = ye;       % To record the initial position

    for i=1:100000000
        dx = k * randn(1,1) + xshiftvelocity * tjmp;      % nm
        dy = k * randn(1,1) + yshiftvelocity * tjmp;      % nm
        xe = xb+dx;               % nm
        ye = yb+dy;               % nm

        if Mnt == 1               % Monitoring
            figure(Fig)
            s = plot([xb xe],[yb ye],'b-');
            s.Color(4)=0.5;
            pause(0.0001)
        end
    
    
        Dis = (xe-XdN).^2+(ye-YdN).^2;
        [m,n] = min(Dis);
        if m<adR^2
            Xads(j) = xe;
            Yads(j) = ye;
            
            switch DistributionMode
                case 1
                    t_ads = Sub_GeneratePowerLawWithMean(Timeindex, tm_ads, 1); % Adsorption time
                case 2
                    if Timeindex > 0
                        t_ads = Sub_GenerateExponentialWithMean(Timeindex, 1); % 指数分布的参数λ与均值的关系：λ = 1/meanValue
                    else
                        sprintf('Ilegal Timeindex');
                        pause;
                    end
                case 3
                     t_ads = Sub_GenerateUniformWithMean(Timeindex, range, 1);    
             end

            if Mnt == 1             % Monitoring
                figure(Fig)
                viscircles([Xads(j) Yads(j)],adR,'Color','k')
            end

            tclock = tclock+t_ads+tjmp;
            j=j+1;
            
    
        else
            tclock = tclock+tjmp;
        end
            
        xb = xe;                    % the current jumping end behaves as the next jumping beginning
        yb = ye;                    % the current jumping end behaves as the next jumping beginning
    
        if Mnt == 1                 % Monitoring
            if Fig ==  1
                figure(Fig)
                frame = getframe(gcf);
                writeVideo(v,frame);
                
            end
                figure(Fig)
                title(strcat('t = ',num2str(t_tot*(jj-1)*10^3+tclock*10^3),'ms;(',num2str(LmaxJUMP/5*10^(9)), 'nm\times', num2str(LmaxJUMP/5*10^(9)),'nm)'))
        end

        if tclock>=t_tot
    
            t_r = t_ads-(t_tot-(tclock-t_ads));      % subsequent adsorption time in the next frame


            if Mnt == 1      % Monitoring
                if Fig ==  1
                    close(v)
                end
            end

            if isempty(Xads)
                Xads = NaN, Yads = NaN
            end

            break;

        end
   
    end

else
    t_r = tclock-t_tot;
    Xads = xe; Yads = ye;

end


end