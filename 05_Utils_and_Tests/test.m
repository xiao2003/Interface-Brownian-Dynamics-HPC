clear;
clc;

x0 = 1*10^(-6)*rand(1,1)+50*10^(-6);
y0 = 1*10^(-6)*rand(1,1)+50*10^(-6);
x0 = x0 * 1e9 ;   % nm
y0 = y0 * 1e9 ;   % nm
xe = x0;
ye = y0;

D = 10^(-8);
jf = 10^(10);
tau = 1/jf;
k = sqrt(2*D*tau) * 10^9 ;

t_tot = 1;
t_s = 0.02;
f_s = round(t_s * jf); 
n_s = round(t_tot / t_s);

length = 1e4;

X = zeros(1,length); DX = zeros(1,length);
Y = zeros(1,length); DY = zeros(1,length);
Index = zeros(1,1e8);
Index(1) = 1;
X(1) = xe ; DX(1) = 0;
Y(1) = ye ; DY(1) = 0;

xshiftvelocity = 3000;
yshiftvelocity = 0;

sprintf('%f %f',x0,y0);

for i = 1: n_s
    xtmp = xe;
    ytmp = ye;
    for j=1 : f_s
            dx = k * randn(1,1) + xshiftvelocity * tau;      % nm
            dy = k * randn(1,1) + yshiftvelocity * tau;      % nm
            xe = xe+dx;               % nm
            ye = ye+dy;               % nm
    end
    X(i) = xe ; DX(i) = xe - xtmp;
    Y(i) = ye ; DY(i) = ye - ytmp;
end