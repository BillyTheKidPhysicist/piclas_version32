function [unew,vnew]=LinIntPol2D(xmin,xmax,ymin,ymax,u,v)
% ==================================================================
% Description
% ==================================================================
% 

% ==================================================================
% Input
% ==================================================================
%                   :: 

% ==================================================================
% Output
% ==================================================================
%                   :: 

% ==================================================================
% Function Start
% ==================================================================
P(1,1)=xmin;P(1,2)=ymin;
P(2,1)=xmax;P(2,2)=ymin;
P(3,1)=xmax;P(3,2)=ymax;
P(4,1)=xmin;P(4,2)=ymax;

unew=0.25*(P(1,1)*(1-v)*(1-u)+P(2,1)*(1-v)*(1+u)+...
           P(3,1)*(1+v)*(1+u)+P(4,1)*(1+v)*(1-u));

vnew=0.25*(P(1,2)*(1-v)*(1-u)+P(2,2)*(1-v)*(1+u)+...
           P(3,2)*(1+v)*(1+u)+P(4,2)*(1+v)*(1-u));

end