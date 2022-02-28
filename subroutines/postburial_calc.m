function Resultmodel = postburial_calc(Perr,para,Model,Prod,nuclide,n)
% This function uses the production rate, and sample data to compute the
% postburial production profiles for stratigraphic sections.
% Input: 
%           - Perr: structure with all production rate uncertainties
%           generated with Puncerts.m function 
%           - para: structure with all sample data generated with
%           assignData.m function
%           - Model: structure with all data for burial model generated
%           with assignData.m
%           - Prod: structure with all production rate data generated by
%           ProductionParas.m
%           - nuclide: e.g. '10Be', '36Cl' etc.
%           - n: number of forward models for MC routine
%
% The speed and precision of the code are mainly controlled by the number
% of runs but also the thickness of individual layers (line 79/80).
%
% Richard Ott, 2021
v2struct(para)
v2struct(Prod)
v2struct(Perr)
global scaling_model

% Final Storage matrix for postburial production at sample depth
PostProduction = zeros(1,n);

% draw random production rates before loop to speed up computation,
% truncate normal distribution to avoid negative production rates
Ps_rand  = truncnormrnd([n,1],0,Ps_uncert ,-1,1);
Pmu_rand = truncnormrnd([n,1],0,Pmu_uncert,-1,1);
if strcmpi(nuclide,'36Cl')
    Pth_rand  = truncnormrnd([n,1],0,Pth_uncert ,-1,1);
    Peth_rand = truncnormrnd([n,1],0,Peth_uncert,-1,1);
end
        

% Initialize a progress bar to monitor the progression of the number of simulations n
wb = waitbar(0,'Welcome to the jungle...');

for i = 1:n
        % RANDOM SAMPLING ----------------------------------------------- %
        % Random sampling of the different parameters from a normal distribution 
        % for each of the n realisations of the simulation. The ages of the
        % core are sampled randomly within the uncertainty bounds of the 
        % dating provided to the function in Depth_age to avoid computational
        % problems the normal distribution gets truncated at 3 sigma
        section_depth = round(truncnormrnd(1,depth(end),depth_uncert(end),depth(end)-3*depth_uncert(end), depth(end)+3*depth_uncert(end)));  % depth in cm 
        Depth_age_guess = [[depth(1:end-1);section_depth],round(normrnd(age,age_uncert))];	% depth, age, matrix

        % if there's an age inversion, take a new sample
        counter = 0;
        while any(diff(Depth_age_guess(:,2)) <= 1) || any(Depth_age_guess(:,2)<0) || any(diff(Depth_age_guess(:,1)) <= 5)
            section_depth = round(truncnormrnd(1,depth(end),depth_uncert(end),depth(end)-3*depth_uncert(end), depth(end)+3*depth_uncert(end)));  % depth in cm
            Depth_age_guess = [[depth(1:end-1);section_depth],round(normrnd(age,age_uncert))];
            counter = counter + 1;
            if counter > 1e4
                error("Couldn't sample a sequence without age inversion. Check your age priors. ")
            end
        end

        % assemble random production rates
        switch nuclide
            case '10Be'
                Ps  = Ps10  + Ps10  .* Ps_rand(i);
                Pmu = Pmu10 + Pmu10 .* Pmu_rand(i);
            case '36Cl'
                Ps   = Ps36  + Ps36    .* Ps_rand(i);
                Pmu  = Pmu36 + Pmu36   .* Pmu_rand(i);
                Pth  = Pth36  + Pth36  .* Pth_rand(i);
                Peth = Peth36 + Peth36 .* Peth_rand(i);               
        end
        %
        % First part of the routine
        % A random sediment layer sequence is built from the random age and
        % depths just drawn
        
        Intervals = diff(Depth_age_guess);
        [r,~] = size(Intervals);
        Sed_col = [];
        for j  = 1:r                                        % loop through packages of stratigraphic section
%             tmp_thickness = ones(round(Intervals(j,1)*rho),1);  % make 1 g/cm2 thick layers
            tmp_thickness = 10*ones(round(Intervals(j,1)*rho/10),1);  % make 10 g/cm2 thick layers, this line makes the code a bit less accurate but 10 times faster
            tmp_time = (Intervals(j,2)/length(tmp_thickness))* ones(length(tmp_thickness),1);   % time within each layer (yrs) 
            
            % The data of this section is attached on top of the data from the previous section
            Sed_col = [[tmp_thickness,tmp_time] ; Sed_col]; % bind all data together
        end

        % Second part of the routine
        % The postdepositional nuclide production can be computed for the 
        % simulated core based on the depth/age constrain imposed by the 
        % Sed_col matrix.
        % The production of nuclides is computed from bottom to top (the 
        % loop indices decreases). Each part of the loop calculates the 
        % nuclide production of a given layer as well as all layers under it.
        % Each iteration is then summed with the previous one
        Sed_col(:,3) = Depth_age_guess(end,2) - flipud(cumsum(Sed_col(:,2)));  % age of every layer in yrs
        section_depth_gcm2 = sum(Sed_col(:,1));  % convert to g/cm2 to match production rate tables
        profile = zeros(section_depth_gcm2,1);
        for k =  length(Sed_col):-1:1
            % For each layer temporary depth, density, time and concentration vectors are created
            tmp_depth = 1:sum(Sed_col(length(Sed_col):-1:k,1));
            tmp_time  = repmat(Sed_col(k,2), length(tmp_depth),1);
            
            % get mean depositional age of this layer for correction
            % scaling factor
            tmp_age = Sed_col(k,3);
            
            % get index of production rate column that is closest in age to tmp_age
            Pind = round(tmp_age/1e2)+1;  
            if Pind > round(max_age/1e2)
                error('The random sample is older than the oldest computed production rate. Increase the safety factor for max_age or use a truncated normal distribution for drawing the samples')
            end
            % calculate production of nuclides
            switch nuclide
                case '10Be'
                    tmp_conc = (Ps(tmp_depth,Pind) + Pmu(tmp_depth,Pind)).*tmp_time;  % Production at/g
                    tmp_conc = tmp_conc.* exp(-tmp_time.*lambda);      % radioactive decay
                case '36Cl'
                    tmp_conc = (Ps(tmp_depth,Pind) + Pmu(tmp_depth,Pind) + ...
                        Peth(tmp_depth,Pind) + Pth(tmp_depth,Pind)).*tmp_time;       % Production at/g
                    tmp_conc = tmp_conc.* exp(-tmp_time.*lambda);      % radioactive decay
            end

            % The result is added to the production vector
            profile((section_depth_gcm2-length(tmp_depth)+1):section_depth_gcm2) = profile((section_depth_gcm2-length(tmp_depth)+1):section_depth_gcm2) + tmp_conc;
        end
        
        % add production after end of deposition
        if Depth_age_guess(1,2) ~= 0 % if there is a no-deposition period at the end
            Pind = round(Depth_age_guess(1,2)/1e2);
            switch nuclide
                case '10Be'
                    postaggradation = (sum(Ps(1:section_depth_gcm2,1:Pind) + ...
                        Pmu(1:section_depth_gcm2,1:Pind),2).*1e2);        % Production at/g
                case '36Cl'
                    postaggradation = (sum(Ps(1:section_depth_gcm2,1:Pind) + ...
                        Pmu(1:section_depth_gcm2,1:Pind) + Pth(1:section_depth_gcm2,1:Pind) ...
                    + Peth(1:section_depth_gcm2,1:Pind),2).*1e2);        % Production at/g
            end
            % add to profile and radioavtive decay
            profile = profile + postaggradation.* exp(-Depth_age_guess(1,2).*lambda);
        end
        
        PostProduction(i) = profile(end);
    % Increment progress bar
    waitbar(i/(n),wb)
end
close(wb)

Resultmodel = Model;
% add all parameters to model
Resultmodel.scaling_model = scaling_model;
Resultmodel.Ps_uncert   = Ps_uncert;
Resultmodel.Pmu_uncert  = Pmu_uncert;
Resultmodel.nruns = n;
Resultmodel.Pmean = round(mean(PostProduction));
Resultmodel.Pmedian = round(median(PostProduction));
Resultmodel.Pstd = round(std(PostProduction));
Resultmodel.Pquartiles = round(quantile(PostProduction,[0.25,0.75]));
Resultmodel.Pquantiles = round(quantile(PostProduction,[0.17,0.83]));
disp(['postburial production ' name{1} ' = ' num2str(Resultmodel.Pmean) ' +/- ' num2str(Resultmodel.Pstd)]) 
disp(['postburial production median ' name{1} ' = ' num2str(Resultmodel.Pmedian) ' +/- ' num2str(diff(Resultmodel.Pquantiles)/2)]) 
disp(['postburial production quantiles ' name{1} ' = ' num2str(Resultmodel.Pquantiles(1)) ' - ' num2str(Resultmodel.Pquantiles(2))]) 

end

