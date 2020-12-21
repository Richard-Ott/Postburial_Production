function out = stdatm(z);% stdatm.m%% Syntax: pressure = stdatm(elevation)%% Units: elevation in m; pressure in hPa; accepts vector arguments%% This function converts elevation to atmospheric pressure according% to the "standard atmosphere" (cf. CRC Handbook of Chem and Phys). %% Greg Balco -- UW Cosmogenic Isotope Lab% First version, Feb. 2001% checked March, 2006 as part of the CRONUS-Earth Be-10/Al-26 % calculators. % define constantsgmr = -0.03417;Ts = 288.15;dtdz = 0.0065;Ps = 1013.25;% calculationout_1 = Ps .* exp( (gmr/dtdz) .* ( log(Ts) - log(Ts - (z.*dtdz)) ) );% return a row vector% MODIFIED BY RO BECAUSE I WANTED TO PRESERVE ORIGINAL SIZE!!!if size(out_1,1) > size(out_1,2);	out = out_1;   % REMOVED THE TRANSPOSITION HEREelse;	out = out_1;end;end