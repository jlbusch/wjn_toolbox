function D=wjn_cfc(filename,timewindow,flow,fhigh,conds)
% D=wjn_cfc(filename,timewindow,flow,fhigh,conds)

% Compute GLM for phase-amplitude and amplitude-amplitude coupling
% FORMAT spm_eeg_cfc(S)
%
% Xamp = independent variable to be explained:
%        Xamp = B1*sin(Xphase) + B2*cos(Xphase) + B3*Xlowamp
%
% Additional regressors may be included
% - overall estimates of PAC & AMP are obtained from continuous (or
%   concatenated) data
% - statistical inference of these estimates is performed by dividing the
%   continuous time series into shorter epochs
% - function writes out images of the estimated PAC & AMP, as well as their
%   p-values
%__________________________________________________________________________
%
% References:
% van Wijk et al. (submitted)
%__________________________________________________________________________
% Copyright (C) 2014 Wellcome Trust Centre for Neuroimaging

% Bernadette van Wijk, Vladimir Litvak
% $Id: spm_eeg_cfc.m 6211 2014-09-29 10:17:49Z vladimir $



D=spm_eeg_load(filename);
if isempty(timewindow)
    timewindow = [D.time(1) D.time(end)];
end
[fdir,fname]=fileparts(D.fullfile);
ichs = [D.indchantype('LFP'),D.indchantype('EEG'),D.indchantype('MEG')];
chs = D.chanlabels(ichs);

if ~exist('conds','var') || (ischar(conds) && strcmp(conds,'all'))
    conds = D.condlist;
else
    conds = channel_finder(conds,D.condlist);
end


i = ci(conds,D.conditions);
iconds = D.conditions(i);
d = D.ftraw(ichs);
if D.fsample > 600
    w_fs = 600;
else
    w_fs = D.fsample;
end
% keyboard
cfg = [];
cfg.method = 'wavelet';
cfg.toi = timewindow(1):1/w_fs:timewindow(2);
cfg.padding = 2;
cfg.foi = [flow fhigh];
cfg.trials = i;
cfg.channels = chs;
cfg.output = 'fourier';
cfg.keeptrials = 'yes';
% cfg.pad = 'nextpow2';
freq = ft_freqanalysis(cfg,d);

phase = freq;
phase.powspctrm=angle(phase.fourierspctrm);
amp = freq;
amp.powspctrm = abs(amp.fourierspctrm);
Dp = spm_eeg_ft2spm(phase,fullfile(fdir,['cfcPH_' fname]));
Dp  = transformtype(Dp,'TFphase');
Dp = chanlabels(Dp,':',chs);
Dp = conditions(Dp,':',iconds);
save(Dp)

Da = spm_eeg_ft2spm(amp,fullfile(fdir,['cfcTF_' fname]));
Da = chanlabels(Da,':',chs);
Da = conditions(Da,':',iconds);
save(Da)
clear phase amp
if numel(conds)>1
conds{end+1} = D.condlist;
end
phlow = find(~isnan(squeeze(Da(1,Da.indfrequency(flow(1)),:,1))),1,'first');

% os = [Da.time(phlow+1+round(Da.fsample/3)) Da.time(end-phlow-1-round(Da.fsample/3))];

%% start run through channels and conditions
for a =1:length(chs)
    for b = 1:length(conds)
keep timewindow flow fhigh nd np Dp Da D conds chs a b phlow phigh os
S=[];
S.D = Da.fullfile;
S.conditions = conds{b};
S.freqwin = fhigh;
S.channels = chs(a);
S.confounds = {};
S.prefix = 'pac_';
S.regressors{1}.tfphase.Dtf = Dp.fullfile;
S.regressors{1}.tfphase.channels{1}.chan = chs(a);
S.regressors{1}.tfphase.timewin = [-Inf Inf];
S.regressors{1}.tfphase.freqwin = flow;
S.regressors{1}.tfphase.average = 0;
S.regressors{1}.tfphase.standardize = 0;
S.regressors{1}.tfphase.regname = 'TFphase';

D = spm_eeg_load(S.D);

if ~isfield(S, 'conditions') || isempty(S.conditions),  S.conditions = D.condlist;  end
if ~iscell(S.conditions), S.conditions = {S.conditions};                            end

allamp   = [];
allphase = [];
cnt      = 1;
for i = 1:numel(S.regressors)
    fun       = char(fieldnames(S.regressors{i}));
    S1{cnt}   = S.regressors{i}.(fun);
    S1{cnt}.D = D;
    S1{cnt}.summarise = false;
    res       =  feval(['spm_eeg_regressors_' fun], S1{cnt});
    cnt       = cnt + 1;
    switch fun
        case 'tfpower'
            allamp   = spm_cat_struct(allamp, res);
        case 'tfphase'
            allphase = spm_cat_struct(allphase, res);
    end
end

allconfounds = [];
% for i = 1:numel(S.confounds)
%     fun  = char(fieldnames(S.confounds{i}));
%     S1{cnt}   = S.confounds{i}.(fun);
%     S1{cnt}.D = D;
%     S1{cnt}.summarise = false;
%     res =  feval(['spm_eeg_regressors_' fun], S1{cnt});
%     cnt=cnt+1;
%     allconfounds   = spm_cat_struct(allconfounds, res);
%     cnt = cnt + 1;
% end

freqind = D.indfrequency(min(S.freqwin)):D.indfrequency(max(S.freqwin));
% keyboard
if isempty(freqind) || any(isnan(freqind))
    error('Selected frequency window is invalid.');
end

data = spm_squeeze(nanmean(D(D.selectchannels(S.channels), freqind, :, D.indtrial(S.conditions, 'GOOD')), 1), 1);
% keyboard
cut  = round(D.fsample/4); %removed at start and end of each filter time series to avoid filter ringing - for trial type data this means a loss of samples per trial


if phlow>1
    cut = phlow+1;
end

% keyboard
if size(data,3)>1
    datatype     = 'trials';
    trialsamples = size(data, 2)-2*cut+1;
    nepochs      = size(data,3);
    totalsamples = trialsamples*nepochs;
    disp(['number of epochs used for statistics: ', num2str(nepochs)]);
else
    datatype     = 'continuous';
    totalsamples = size(data, 2)-2*cut+1;
    trialsamples = round(window*D.fsample);
    nepochs      = floor(totalsamples/trialsamples);
    disp(['number of epochs used for statistics: ', num2str(nepochs)]);
end


%-Get amplitude timeseries
%--------------------------------------------------------------------------
Famp = D.frequencies(freqind);
for N = 1:length(freqind)
    fprintf('\nF amp = %.1f |\t', Famp(N));
    
    if strcmp(datatype,'trials')
        for k = 1:size(data, 3)
            amp_high = data(N, cut:end-cut, k);
            AMP(N,(k-1)*trialsamples+1:k*trialsamples) = amp_high;
            amp(N,k,:) = (amp_high - nanmean(amp_high))./nanstd(amp_high);
        end
        AMP(N,:) = (AMP(N,:) - nanmean(AMP(N,:)))./nanstd(AMP(N,:));
        
    elseif strcmp(datatype,'continuous')
        
        amp_high = data(N, cut:end-cut);
        AMP(N,:) = amp_high;
        for k = 1:nepochs
            amp(N,k,:) = AMP(N,(k-1)*trialsamples+1:k*trialsamples);
            amp(N,k,:) = (amp(N,k,:)-nanmean(amp(N,k,:)))./nanstd(amp(N,k,:));
        end
        AMP(N,:) = (AMP(N,:)-nanmean(AMP(N,:)))./nanstd(AMP(N,:));
    end
    
end

nsamples = size(data, 2);

if strcmp(datatype,'trials')
    bad  = spm_squeeze(any(D.badsamples(D.selectchannels(S.channels), cut:D.nsamples-cut, D.indtrial(S.conditions, 'GOOD')), 1), 1);
    BAD  = zeros(1, size(AMP, 2));
    for k = 1:size(bad, 2)
        BAD((k-1)*trialsamples+1:k*trialsamples) = bad(:, k);
    end
elseif strcmp(datatype,'continuous')
    BAD  = spm_squeeze(any(D.badsamples(D.selectchannels(S.channels), ':', 1), 1), 1);
    BAD  = BAD(cut:end-cut);
    
    bad = zeros(size(amp, 2), size(amp, 3));
    for k = 1:nepochs
        bad(k, :)  = BAD((k-1)*trialsamples+1:k*trialsamples);
    end
end
bad = bad';

%-Get phase time series
%--------------------------------------------------------------------------
SINE = {};
sine = {};
COSINE = {};
cosine = {};

for i = 1:numel(allphase)
    PHASE = allphase(i).R;
    
    nphase = 0.5*size(PHASE, 2);
    
    for j = 1:nphase
        
        ind = max(strfind(allphase(i).names{j}, '_'));
        phasefreq(i, j) = sscanf(allphase(1).names{j}(ind+1:end), '%fHz');
        fprintf('\nF phase = %.1f |\t',  phasefreq(i, j));
        
        if strcmp(datatype,'trials')
            for k = 1:size(data, 3)
                phase_low = PHASE(((k-1)*nsamples+1):k*nsamples, j) ;
                SINE{i}(j,(k-1)*trialsamples+1:k*trialsamples) = phase_low(cut:end-cut);
                sine{i}(j,k,:) = phase_low(cut:end-cut);
                sine{i}(j,k,:) = (sine{i}(j,k,:)-nanmean(sine{i}(j,k,:)))./nanstd(sine{i}(j,k,:));
                
                phase_low = PHASE(((k-1)*nsamples+1):k*nsamples, j + nphase) ;
                COSINE{i}(j,(k-1)*trialsamples+1:k*trialsamples) = phase_low(cut:end-cut);
                cosine{i}(j,k,:) = phase_low(cut:end-cut);
                cosine{i}(j,k,:) = (cosine{i}(j,k,:)-nanmean(cosine{i}(j,k,:)))./nanstd(cosine{i}(j,k,:));
            end
            SINE{i}(j,:)=(SINE{i}(j,:)-nanmean(SINE{i}(j,:)))./nanstd(SINE{i}(j,:));
            COSINE{i}(j,:)=(COSINE{i}(j,:)-nanmean(COSINE{i}(j,:)))./nanstd(COSINE{i}(j,:));
            
        elseif strcmp(datatype,'continuous')
            phase_low = PHASE(:, j) ;
            SINE{i}(j,:) = phase_low(cut:end-cut);
            
            phase_low = PHASE(:, j+nphase) ;
            COSINE{i}(j,:) = phase_low(cut:end-cut);
            for k = 1:nepochs
                sine{i}(j, k,:)   = SINE(j,(k-1)*trialsamples+1:k*trialsamples);
                cosine{i}(j, k,:) = COSINE(j,(k-1)*trialsamples+1:k*trialsamples);
                sine{i}(j,k,:)   = (sine{i}(j,k,:)-nanmean(sine{i}(j,k,:)))./nanstd(sine{i}(j,k,:));
                cosine{i}(j,k,:) = (cosine{i}(j,k,:)-nanmean(cosine{i}(j,k,:)))./nanstd(cosine{i}(j,k,:));
            end
            SINE{i}(j,:)=(SINE{i}(j,:)-nanmean(SINE{i}(j,:)))./nanstd(SINE{i}(j,:));
            COSINE{i}(j,:)=(COSINE{i}(j,:)-nanmean(COSINE{i}(j,:)))./nanstd(COSINE{i}(j,:));
        end
    end
end

%-Get amplitude time series for low frequencies
%--------------------------------------------------------------------------
AMP_LOW = {};
amp_low = {};

for i = 1:numel(allamp)
    
    namp = size(allamp(i).R, 2);
    
    for j = 1:namp
        ind = max(strfind(allamp(i).names{j}, '_'));
        ampfreq(i, j) =  sscanf(allamp(1).names{j}(ind+1:end), '%fHz');
        fprintf('\nF low amp = %.1f |\t', ampfreq(i, j));
        
        if strcmp(datatype,'trials')
            for k = 1:size(data, 3)
                
                amplow = allamp(i).R(((k-1)*nsamples+1):k*nsamples, j);
                AMP_LOW{i}(j,(k-1)*trialsamples+1:k*trialsamples)=amplow(cut:end-cut);
                amp_low{i}(j,k,:)=(amplow(cut:end-cut)-nanmean(amplow(cut:end-cut)))./nanstd(amplow(cut:end-cut));
                
            end
            AMP_LOW{i}(j,:)=(AMP_LOW{i}(j,:)-nanmean(AMP_LOW{i}(j,:)))./nanstd(AMP_LOW{i}(j,:));
            
        elseif strcmp(datatype,'continuous')
            
            amplow= allamp(i).R(:, j);
            AMP_LOW{i}(j,:)=amplow(cut:end-cut);
            for k=1:nepochs
                amp_low{i}(j,k,:)=AMP_LOW{i}(j,(k-1)*trialsamples+1:k*trialsamples);
                amp_low{i}(j,k,:)=(amp_low{i}(j,k,:)-nanmean(amp_low{i}(j,k,:)))./nanstd(amp_low{i}(j,k,:));
            end
            AMP_LOW{i}(j,:)=(AMP_LOW{i}(j,:)-nanmean(AMP_LOW{i}(j,:)))./nanstd(AMP_LOW{i}(j,:));
        end
    end
end

%-Set low frequency axis
%--------------------------------------------------------------------------
if isempty(amp_low); Flow=phasefreq;
elseif isempty(cosine); Flow=ampfreq;
else
    Flow = cat(1, phasefreq, ampfreq);
    % Could this possibly be relaxed?
    if any(any(diff(Flow, [], 1)))
        error('The frequency axes for all regressors should be identical.');
    else
        Flow = Flow(1, :);
    end
end

%-Get time series for confounders
%--------------------------------------------------------------------------
CONFOUNDS = {};
confounds = {};
for i = 1:numel(allconfounds)
    
    nconf = size(allconfounds(i).R, 2);
    
    for j = 1:nconf
        fprintf('\nConfound: %s |\t', allconfounds(i).names{j});
        
        if strcmp(datatype,'trials')
            for k = 1:size(data, 3)
                
                conf = allconfounds(i).R(((k-1)*nsamples+1):k*nsamples, j);
                CONFOUNDS{i}(j,(k-1)*trialsamples+1:k*trialsamples) = conf(cut:end-cut);
                confounds{i}(j,k,:) = (conf(cut:end-cut)-nanmean(conf(cut:end-cut)))./nanstd(conf(cut:end-cut));
                
            end
            CONFOUNDS{i}(j,:)=(CONFOUNDS{i}(j,:)-nanmean(CONFOUNDS{i}(j,:)))./nanstd(CONFOUNDS{i}(j,:));
            
        elseif strcmp(datatype,'continuous')
            
            conf = allconfounds(i).R(:, j);
            CONFOUNDS{i}(j,:) = conf(cut:end-cut);
            for k=1:nepochs
                confounds{i}(j,k,:) = CONFOUNDS{i}(j,(k-1)*trialsamples+1:k*trialsamples);
                confounds{i}(j,k,:)=(confounds{i}(j,k,:)-nanmean(confounds{i}(j,k,:)))./nanstd(confounds{i}(j,k,:));
            end
            CONFOUNDS{i}(j,:) = (CONFOUNDS{i}(j,:)-nanmean(CONFOUNDS{i}(j,:)))./nanstd(CONFOUNDS{i}(j,:));
        end
    end
    if nconf==1&&length(Flow)>1
        CONFOUNDS{i}=repmat(CONFOUNDS{i},length(Flow),1);
        confounds{i}=repmat(confounds{i},[length(Flow),1,1]);
    end
end

fprintf('\n\n')


W        = ones(length(BAD), 1);
W(~~BAD) = exp(-256);
W        = spdiags(W, 0, length(W), length(W));

%-Compute GLM
%--------------------------------------------------------------------------
spm_progress_bar('Init', length(Flow), 'Fitting GLM', 'Frequency nr');

for j=1:length(Flow)
%     fprintf('%.1f  ',Flow(j))
    for N=1:length(Famp)
        
        % GLM for all data appended
        %------------------------------------------------------------------
        
        X=[];
        
        for nph=1:numel(allphase)
            X=[X;SINE{nph}(j,:);COSINE{nph}(j,:)];
        end
        for nam=1:numel(allamp)
            X=[X;AMP_LOW{nam}(j,:)];
        end
        for ncf=1:numel(allconfounds)
            X=[X;CONFOUNDS{ncf}(j,:)];
        end
        
        nreg=size(X,1);
        
        X = X*W;
        
        y = AMP(N,:)*W;
        
        V=[];
        c=ones(nreg,1);
%         keyboard
        all_Beta(N,j,:)=y*pinv(X);
        
        all_SSy(N,j)=sum((y-nanmean(y)).^2);
        
        cnt=1;
        
        for nph=1:numel(allphase)
            all_residuals=y-(all_Beta(N,j,cnt).*X(cnt,:)+all_Beta(N,j,cnt+1).*X(cnt+1,:));
            all_SSe=sum((all_residuals-nanmean(all_residuals)).^2);
            all_r_pac{nph}(N,j)=real(sqrt((all_SSy(N,j)-all_SSe)/all_SSy(N,j)));
            all_Beta_sin{nph}(N,j)=all_Beta(N,j,cnt);
            all_Beta_cos{nph}(N,j)=all_Beta(N,j,cnt+1);
            cnt=cnt+2;
        end
        for nam=1:numel(allamp)
            all_residuals=y-(all_Beta(N,j,cnt).*X(cnt,:));
            all_SSe=sum((all_residuals-nanmean(all_residuals)).^2);
            all_r_amp{nam}(N,j)=real(sqrt((all_SSy(N,j)-all_SSe)/all_SSy(N,j)));
            all_Beta_amp{nam}(N,j)=all_Beta(N,j,cnt);
            cnt=cnt+1;
        end
        for ncf=1:numel(allconfounds)
            all_residuals=y-(all_Beta(N,j,cnt).*X(cnt,:));
            all_SSe=sum((all_residuals-nanmean(all_residuals)).^2);
            all_r_conf{ncf}(N,j)=real(sqrt((all_SSy(N,j)-all_SSe)/all_SSy(N,j)));
            all_Beta_conf{ncf}(N,j)=all_Beta(N,j,cnt);
            cnt=cnt+1;
        end
        
        all_residuals_total=y-(X'*squeeze(all_Beta(N,j,:)))';
        all_SSe_total=sum((all_residuals_total-nanmean(all_residuals_total)).^2);
        all_r_total(N,j)=real(sqrt((all_SSy(N,j)-all_SSe_total)/all_SSy(N,j)));
        
        %-GLM per trial
        %------------------------------------------------------------------
        k_good = 0;
        
        for k = 1:nepochs
            % Exclude epochs with mostly bad data
            if (sum(bad(k, :))/size(bad, 2))<0.5;
                k_good = k_good + 1;
                
                Wk              = ones(size(bad, 2), 1);
                Wk(~~bad(k, :)) = exp(-256);
                Wk = spdiags(Wk, 0, length(Wk), length(Wk));
                
                
                Xk=[];
                
                for nph=1:numel(allphase)
                    Xk=[Xk;squeeze(sine{nph}(j,k,:))';squeeze(cosine{nph}(j,k,:))'];
                end
                for nam=1:numel(allamp)
                    Xk=[Xk;squeeze(amp_low{nam}(j,k,:))'];
                end
                for ncf=1:numel(allconfounds)
                    Xk=[Xk;squeeze(confounds{ncf}(j,k,:))'];
                end
                
                Xk = Xk*Wk;
                
                nreg=size(Xk,1);
                
                yk = Wk*squeeze(amp(N,k,:));
                
                V=[];
                c=ones(nreg,1);
                
                Beta(:,k_good)=(yk'*pinv(Xk));
               
                cnt=1;
                for nph=1:numel(allphase)
                    if S1{nph}.summarise
                        Beta_sin{nph}(N,j,k_good)=Beta(cnt,k_good);
                        Beta_cos{nph}(N,j,k_good)=Beta(cnt+1,k_good);
                        cnt=cnt+2;
                    end
                end
                if isempty(nph);nph=0;end
                for nam=1:numel(allamp)
                    if S1{nph+nam}.summarise
                        Beta_amp{nam}(N,j,k_good)=Beta(cnt,k_good);
                        cnt=cnt+1;
                    end
                end
                if isempty(nam);nam=0;end
                for ncf=1:numel(allconfounds)
                    if S1{nph+nam+ncf}.summarise
                        Beta_conf{ncf}(N,j,k_good)=Beta(cnt,k_good);
                        cnt=cnt+1;
                    end
                end
            end
        end %trials
        
        %-Test for significance
        %------------------------------------------------------------------
        
        cnt=1;
        for nph=1:numel(allphase)
            Xb=[];
            Xb(1:k_good,1)=ones(k_good,1);Xb(k_good+1:2*k_good,2)=ones(k_good,1);
            yb=[Beta(cnt,:),Beta(cnt+1,:)];
            c=[1;1];
            [Tb,df,Beta_b,xX,xCon]=spm_ancova(Xb,V,yb',c);
            F=Tb^2;
            p_pac{nph}(N,j)=1-spm_Fcdf(F,df(1),df(2));
            cnt=cnt+2;
        end
        for nam=1:numel(allamp)
            [H,P] = ttest(Beta(cnt,:));
            p_amp{nam}(N,j)=P;
            cnt=cnt+1;
        end
        for ncf=1:numel(allconfounds)
            [H,P] = ttest(Beta(cnt,:));
            p_conf{ncf}(N,j)=P;
            cnt=cnt+1;
        end
        
        Xb=[];
        yb=[];
        for i=1:nreg
            Xb((i-1)*k_good+1:i*k_good,i)=ones(k_good,1);
            yb=[yb,Beta(i,:)];
        end
        
        c=ones(nreg,1);
        
        [Tb,df,Beta_b,xX,xCon]=spm_ancova(Xb,V,yb',c);
        F_total=Tb^2;
        p_total(N,j)=1-spm_Fcdf(F_total,df(1),df(2));
        
        
    end %N
    
    spm_progress_bar('Set', j);
end %j

spm_progress_bar('Clear');
f1 = Flow;
f2 = Famp;
pac = all_r_pac{1};
p = p_pac{1};

nd(a,:,:,b) = pac;
np(a,:,:,b) = p;
disp([chs{a} ' done!'])
disp([conds{b} ' done!'])
    end
end

%%
if numel(conds)>1
    conds{end} = 'all';
end


dim = size(nd);
if length(dim)==3
    dim(4) =1;
end

D=clone(Da,['pac_' Da.fname],dim);
D.p = np;

D(:,:,:,:) = nd(:,:,:,:);



D=conditions(D,':',conds);
D.f1 = f1;
D.f2 = f2;
D.flow = flow;
D.fhigh = fhigh;
D.timewindow = timewindow;
save(D);
disp('all done!')
%%










%% - Plot results
%--------------------------------------------------------------------------

% outname  = [S.prefix 'cfc_' spm_file(D.fname, 'basename')];
% 
% siglevel=.05;
% cnt=1;
% 
% Fgraph   = spm_figure('GetWin', outname); figure(Fgraph); clf
% 
% nsub=ceil(length(S1))+1;
% 
% for nph=1:numel(allphase)
%     sig_pac{nph}=(p_pac{nph}<=siglevel);
%     subplot(nsub,2,cnt),imagesc(Flow,Famp,all_r_pac{nph}),set(gca,'ydir','normal');title(S1{nph}.regname);colorbar;
%     subplot(nsub,2,cnt+1),imagesc(Flow,Famp,sig_pac{nph}),set(gca,'ydir','normal');title(['significant p<.05']), colorbar;
%     cnt=cnt+2;
% end
% if isempty(nph);nph=0;end
% for nam=1:numel(allamp)
%     sig_amp{nam}=(p_amp{nam}<=siglevel);
%     subplot(nsub,2,cnt),imagesc(Flow,Famp,all_Beta_amp{nam}),set(gca,'ydir','normal');title(S1{nph+nam}.regname);colorbar;
%     subplot(nsub,2,cnt+1),imagesc(Flow,Famp,sig_amp{nam}),set(gca,'ydir','normal');title(['significant p<.05']), colorbar;
%     cnt=cnt+2;
% end
% if isempty(nam);nam=0;end
% for ncf=1:numel(allconfounds)
%     sig_cnf{ncf}=(p_conf{ncf}<=siglevel);
%     subplot(nsub,2,cnt),imagesc(Flow,Famp,all_Beta_conf{ncf}),set(gca,'ydir','normal');title(S1{nph+nam+ncf}.regname);colorbar;
%     subplot(nsub,2,cnt+1),imagesc(Flow,Famp,sig_cnf{ncf}),set(gca,'ydir','normal');title(['significant p<.05']), colorbar;
%     cnt=cnt+2;
% end
% sig_total=(p_total<=siglevel);
% subplot(nsub,2,cnt),imagesc(Flow,Famp,all_r_total),set(gca,'ydir','normal');title('full model');colorbar;
% subplot(nsub,2,cnt+1),imagesc(Flow,Famp,sig_total),set(gca,'ydir','normal');title(['significant p<.05']), colorbar;
% 

% sig = sig_pac;

%%
% 
% %-Write out images
% %--------------------------------------------------------------------------
% 
% cnt=1;
% 
% for nph=1:numel(allphase)
%     image(cnt).val     = all_r_pac{nph};
%     image(cnt).label   = ['r_pac_reg',num2str(nph)];
%     cnt=cnt+1;
%     image(cnt).val     = p_pac{nph};
%     image(cnt).label   = ['p_pac_reg',num2str(nph)];
%     cnt=cnt+1;
%     image(cnt).val     = sig_pac{nph};
%     image(cnt).label   = ['sig_pac_reg',num2str(nph)];
%     cnt=cnt+1;
%     image(cnt).val     = all_Beta_sin{nph};
%     image(cnt).label   = ['r_Bsin_reg',num2str(nph)];
%     cnt=cnt+1;
%     image(cnt).val     = all_Beta_cos{nph};
%     image(cnt).label   = ['r_Bcos_reg',num2str(nph)];
%     cnt=cnt+1;
%     
%     if S1{nph}.summarise
%         for k=1:nepochs
%             image(cnt).val = squeeze(Beta_sin{nph}(:,:,k));
%             image(cnt).label   = ['trial',num2str(k),'_Bsin_reg',num2str(nph)];
%             cnt=cnt+1;
%             image(cnt).val = squeeze(Beta_cos{nph}(:,:,k));
%             image(cnt).label   = ['trial',num2str(k),'_Bcos_reg',num2str(nph)];
%             cnt=cnt+1;
%         end
%     end
% end
% if isempty(nph),nph=0;end
% for nam=1:numel(allamp)
%     image(cnt).val     = all_Beta_amp{nam};
%     image(cnt).label   = ['c_amp_reg',num2str(nam)];
%     cnt=cnt+1;
%     image(cnt).val     = p_amp{nam};
%     image(cnt).label   = ['p_amp_reg',num2str(nam)];
%     cnt=cnt+1;
%     image(cnt).val     = sig_amp{nam};
%     image(cnt).label   = ['sig_amp_reg',num2str(nam)];
%     cnt=cnt+1;
%     
%     if S1{nph+nam}.summarise
%         for k=1:nepochs
%             image(cnt).val = squeeze(Beta_amp{nam}(:,:,k));
%             image(cnt).label   = ['trial',num2str(k),'_Bamp_reg',num2str(nam)];
%             cnt=cnt+1;
%         end
%     end
% end
% 
% if isempty(nam),nam=0;end
% for ncf=1:numel(allconfounds)
%     image(cnt).val     = all_Beta_conf{ncf};
%     image(cnt).label   = ['r_conf_reg',num2str(ncf)];
%     cnt=cnt+1;
%     image(cnt).val     = p_conf{ncf};
%     image(cnt).label   = ['p_conf_reg',num2str(ncf)];
%     cnt=cnt+1;
%     image(cnt).val     = sig_conf{ncf};
%     image(cnt).label   = ['sig_conf_reg',num2str(ncf)];
%     cnt=cnt+1;
%     
%     if S1{nph+nam+ncf}.summarise
%         for k=1:nepochs
%             image(cnt).val = squeeze(Beta_conf{ncf}(:,:,k));
%             image(cnt).label   = ['trial',num2str(k),'_Bconf_reg',num2str(ncf)];
%             cnt=cnt+1;
%         end
%     end
% end
% 
% 
% 
% image(cnt).val     = all_r_total;
% image(cnt).label   = ['r_total'];
% cnt=cnt+1;
% image(cnt).val     = p_total;
% image(cnt).label   = ['p_total'];
% cnt=cnt+1;
% image(cnt).val     = sig_total;
% image(cnt).label   = ['sig_total'];
% 
% % 
% % 
% % %% -Write out images
% % %==========================================================================
% % [sts, msg] = mkdir(D.path, outname);
% % if ~sts,     error(msg); end
% % 
% % outdir = fullfile(D.path, outname);
% % 
% % if length(Famp)>1
% %     dFamp = Famp(2)-Famp(1);
% % else
% %     dFamp = 0;
% % end
% % 
% % if length(Flow)>1
% %     dFlow = Flow(2)-Flow(1);
% % else
% %     dFlow = 0;
% % end
% % 
% % N     = nifti;
% % N.mat_intent = 'Aligned';
% % N.mat = [...
% %     dFamp   0               0  Famp(1);...
% %     0       dFlow           0  Flow(1);...
% %     0       0               1  0;...
% %     0       0               0  1];
% % N.mat(1,4) = N.mat(1,4) - N.mat(1,1);
% % N.mat(2,4) = N.mat(2,4) - N.mat(2,2);
% % 
% % spm_progress_bar('Init', numel(image), 'Writing out images', 'Image');
% % for i = 1:numel(image)
% %     N.dat = file_array(fullfile(outdir, [image(i).label '.nii']), size(image(i).val), 'FLOAT32-LE');
% %     create(N);
% %     N.dat(:, :) = image(i).val;
% %     
% %     spm_progress_bar('Set', i);
% % end
% % 
% % %-Cleanup
% % %--------------------------------------------------------------------------
% % spm_progress_bar('Clear');
% % spm('FigName','Cross-frequency coupling: done'); spm('Pointer','Arrow');
