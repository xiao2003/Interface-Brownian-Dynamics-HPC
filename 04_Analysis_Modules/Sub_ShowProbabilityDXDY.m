function [] = Sub_ShowProbabilityDXDY(FN,DTRACK,FigN,coco)
% To plot the distribution of DX/DY
% DTRACK: the maximum tracking length: nm

fontsize = 14;


%% To load and prepare the data
load(FN,'DX','DY');
% To remove the NaN from DX/DY
DXX = DX;
DXX(isnan(DXX)) = 0; DXX = DXX(find(DXX));
DYY = DY;
DYY(isnan(DYY)) = 0; DYY = DYY(find(DYY));

%% To plot the distributions of absolute dx/dy
figure(FigN)
title('Displacement distribution')
hold on

[j,d] = hist(DXX(:), linspace(-DTRACK,DTRACK,DTRACK/10));
% plot(d,j,'.', 'MarkerSize', 20,'Color',coco);
[h,c] = hist(DYY(:),linspace(-DTRACK,DTRACK,DTRACK/10));
hold on
plot(c,h,'s', 'MarkerSize', 6,'Color',coco,'MarkerFaceColor',coco,'MarkerEdgeColor',coco);
legend('dx','dy')
set(gca,'YScale','log');
xlabel('dx(dy) (nm)');
ylabel('N');
set(gca,'FontSize',20,'FontName','Calibri');
box on
legend('Dx','Dy')
%% To plot the distributions of dx/dy probability

edges = -max(max(DXX)):max(max(DXX))/20:max(max(DXX)); % to define the edge of bins of DL
% edges = linspace(-DTRACK,DTRACK,DTRACK/10); % to define the edge of bins of DL
figure(FigN+1)
title('dx(dy) Probability')
h1 = histogram(DXX(:),edges,'Normalization','probability','DisplayStyle','stairs','LineWidth',2);
xedge1=h1.BinEdges;x1=(xedge1(1:end-1)+xedge1(2:end))/2;
y1=h1.Values;
figure(FigN+2)
hold on
title('dx(dy) Probability')
% plot(x1,y1,'-','LineWidth',2,'Marker','.','MarkerSize',20,'Color',coco)


figure(FigN+1)
title('dx(dy) Probability')
h2 = histogram(DYY(:),edges,'Normalization','probability','DisplayStyle','stairs','LineWidth',2);
xlabel('dx(dy) (nm)')
ylabel('G')
box on
set(gca,'FontSize',fontsize);
set(gca,'YScale','log');
% legend('Dx','Dy')
xedge2=h2.BinEdges;x2=(xedge2(1:end-1)+xedge2(2:end))/2;
y2=h2.Values;
figure(FigN+2)
hold on
plot(x2,y2,'s','MarkerSize', 6,'Color',coco,'MarkerFaceColor',coco,'MarkerEdgeColor',coco)
xlabel('dx(dy) (nm)')
ylabel('G')
box on
set(gca,'FontSize',20,'FontName','Calibri');
set(gca,'YScale','log');
% legend('Dx','Dy')


end